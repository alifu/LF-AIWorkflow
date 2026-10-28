//
//  HotkeySpecTests.swift
//  LF-AIWorkflowTests
//

import Carbon.HIToolbox
import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct HotkeySpecTests {
    @Test func presetsStartWithTheDefaultAndAllValidate() {
        #expect(HotkeySpec.presets.first == .default)
        #expect(HotkeySpec.presets.count == 3)
        for spec in HotkeySpec.presets { #expect(spec.validate() == .valid, "\(spec.displayString)") }
        #expect(Set(HotkeySpec.presets).count == 3)
    }

    @Test func displayStringsUseMenuSymbols() {
        #expect(HotkeySpec.optionCommandSpace.displayString == "⌥⌘Space")
        #expect(HotkeySpec.controlOptionSpace.displayString == "⌃⌥Space")
        #expect(HotkeySpec.optionCommandN.displayString == "⌥⌘N")
    }

    @Test func shiftOnlyOrNoModifierIsRejected() {
        #expect(HotkeySpec(keyCode: 49, modifiers: 0).validate() == .missingModifier)
        #expect(HotkeySpec(keyCode: 49, modifiers: UInt32(shiftKey)).validate() == .missingModifier)
    }

    @Test func modifierKeyAsTheKeyIsRejected() {
        #expect(HotkeySpec(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)).validate() == .modifierOnlyKey)
        #expect(HotkeySpec(keyCode: UInt32(kVK_Option), modifiers: UInt32(optionKey)).validate() == .modifierOnlyKey)
    }

    @Test func storeFallsBackToDefaultForAnInvalidStoredHotkey() throws {
        let suite = "lf-hotkey-test-\(UUID().uuidString)"
        let bad = HotkeySpec(keyCode: 49, modifiers: 0)
        UserDefaults(suiteName: suite)!.set(try JSONEncoder().encode(bad), forKey: SettingsStore.Keys.hotkey)
        #expect(SettingsStore(suiteName: suite).hotkey == .default)
    }

    @Test func noticeAppearsOnlyWhenRegistrationFailed() {
        let store = SettingsStore(suiteName: "lf-hotkey-test-\(UUID().uuidString)")
        #expect(store.hotkeyNotice == nil)
        store.hotkeyRegistered = false
        let notice = store.hotkeyNotice ?? ""
        #expect(notice.contains("⌥⌘Space"))
        store.hotkeyRegistered = true
        #expect(store.hotkeyNotice == nil)
    }
}

// MARK: - HotkeyManager

@MainActor
private final class FakeHotkey: HotkeyRegistering {
    let spec: HotkeySpec
    let log: Log
    let succeeds: Bool
    var isRegistered = false
    init(spec: HotkeySpec, log: Log, succeeds: Bool) { self.spec = spec; self.log = log; self.succeeds = succeeds }

    func register() -> Bool {
        log.events.append("register \(spec.displayString)")
        isRegistered = succeeds
        return succeeds
    }

    func unregister() {
        guard isRegistered else { return }
        isRegistered = false
        log.events.append("unregister \(spec.displayString)")
    }

    final class Log { var events: [String] = []; var made: [FakeHotkey] = [] }
}

@MainActor
struct HotkeyManagerTests {
    private func make(refusing: Set<HotkeySpec> = []) -> (HotkeyManager, FakeHotkey.Log) {
        let log = FakeHotkey.Log()
        let manager = HotkeyManager(factory: { spec, _ in
            let key = FakeHotkey(spec: spec, log: log, succeeds: !refusing.contains(spec))
            log.made.append(key)
            return key
        }, action: {})
        return (manager, log)
    }

    @Test func registersTheFirstSpec() {
        let (manager, log) = make()
        #expect(manager.apply(.optionCommandSpace))
        #expect(log.events == ["register ⌥⌘Space"])
        #expect(manager.activeSpec == .optionCommandSpace)
    }

    @Test func changingTheSpecRegistersTheNewOneThenUnregistersTheOldExactlyOnce() {
        let (manager, log) = make()
        manager.apply(.optionCommandSpace)
        #expect(manager.apply(.optionCommandN))
        #expect(log.events == ["register ⌥⌘Space", "register ⌥⌘N", "unregister ⌥⌘Space"])
        #expect(log.made.filter(\.isRegistered).count == 1)
        #expect(manager.activeSpec == .optionCommandN)
    }

    @Test func reapplyingTheSameSpecDoesNothing() {
        let (manager, log) = make()
        manager.apply(.optionCommandSpace)
        #expect(manager.apply(.optionCommandSpace))
        #expect(log.events == ["register ⌥⌘Space"])
    }

    @Test func refusedSpecReportsFailureAndKeepsTheOldHotkeyRegistered() {
        let (manager, log) = make(refusing: [.controlOptionSpace])
        manager.apply(.optionCommandSpace)
        #expect(!manager.apply(.controlOptionSpace))
        #expect(manager.activeSpec == .optionCommandSpace)
        #expect(log.made.filter(\.isRegistered).map(\.spec) == [.optionCommandSpace])
        #expect(!log.events.contains("unregister ⌥⌘Space"))
    }

    @Test func refusedSpecSetsTheNoticeWhileTheOldHotkeyStillWorks() {
        let (manager, _) = make(refusing: [.controlOptionSpace])
        let store = SettingsStore(suiteName: "HotkeyKeep-\(UUID().uuidString)")
        manager.apply(.optionCommandSpace)
        store.hotkey = .controlOptionSpace
        store.hotkeyRegistered = manager.apply(store.hotkey)
        #expect(store.hotkeyNotice != nil)
        #expect(manager.activeSpec == .optionCommandSpace)
    }

    @Test func afterAFailureTheSameSpecIsRetried() {
        let (manager, log) = make(refusing: [.controlOptionSpace])
        manager.apply(.controlOptionSpace)
        manager.apply(.controlOptionSpace)
        #expect(log.made.count == 2)
    }

    @Test func invalidSpecIsRefusedWithoutCreatingAHotkey() {
        let (manager, log) = make()
        manager.apply(.optionCommandSpace)
        #expect(!manager.apply(HotkeySpec(keyCode: 49, modifiers: 0)))
        #expect(log.made.count == 1)
        #expect(log.made.filter(\.isRegistered).count == 1)
    }

    @Test func stopUnregistersAndAllowsRegisteringAgain() {
        let (manager, log) = make()
        manager.apply(.optionCommandSpace)
        manager.stop()
        #expect(log.made.filter(\.isRegistered).isEmpty)
        #expect(manager.activeSpec == nil)
        #expect(manager.apply(.optionCommandSpace))
        #expect(log.made.count == 2)
    }
}

// MARK: - GlobalHotkey over the Carbon seam (TD-051)

@MainActor
private final class FakeSystem: HotkeySystem {
    var events: [String] = []
    var handlerRefused = false
    var hotKeyRefused = false
    private var nextToken = 1
    var liveHandlers = 0
    var liveHotKeys = 0

    private func token() -> OpaquePointer { defer { nextToken += 1 }; return OpaquePointer(bitPattern: nextToken)! }

    func installHandler(owner: UnsafeMutableRawPointer) -> EventHandlerRef? {
        events.append("install")
        guard !handlerRefused else { return nil }
        liveHandlers += 1
        return token()
    }

    var registeredIDs: [UInt32] = []
    func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        registeredIDs.append(id)
        events.append("register \(keyCode)/\(modifiers)")
        guard !hotKeyRefused else { return nil }
        liveHotKeys += 1
        return token()
    }

    func unregisterHotKey(_ ref: EventHotKeyRef) { events.append("unregisterHotKey"); liveHotKeys -= 1 }
    func removeHandler(_ ref: EventHandlerRef) { events.append("removeHandler"); liveHandlers -= 1 }
}

@MainActor
struct GlobalHotkeyTests {
    @Test func registerInstallsHandlerThenHotKeyWithTheSpec() {
        let system = FakeSystem()
        let hotkey = GlobalHotkey(spec: .optionCommandN, system: system, action: {})
        #expect(hotkey.register())
        #expect(system.events == ["install", "register \(HotkeySpec.optionCommandN.keyCode)/\(HotkeySpec.optionCommandN.modifiers)"])
    }

    @Test func registeringTwiceInstallsOnce() {
        let system = FakeSystem()
        let hotkey = GlobalHotkey(system: system, action: {})
        hotkey.register()
        #expect(hotkey.register())
        #expect(system.liveHotKeys == 1 && system.liveHandlers == 1)
    }

    @Test func unregisterReleasesBoth() {
        let system = FakeSystem()
        let hotkey = GlobalHotkey(system: system, action: {})
        hotkey.register()
        hotkey.unregister()
        hotkey.unregister()
        #expect(system.liveHotKeys == 0 && system.liveHandlers == 0)
    }

    @Test func refusedHotKeyRemovesTheHandlerAgain() {
        let system = FakeSystem()
        system.hotKeyRefused = true
        let hotkey = GlobalHotkey(system: system, action: {})
        #expect(!hotkey.register())
        #expect(system.liveHandlers == 0 && system.liveHotKeys == 0)
    }

    @Test func refusedHandlerFailsWithoutRegisteringAHotKey() {
        let system = FakeSystem()
        system.handlerRefused = true
        let hotkey = GlobalHotkey(system: system, action: {})
        #expect(!hotkey.register())
        #expect(system.events == ["install"])
    }

    @Test func deinitUnregisters() {
        let system = FakeSystem()
        var hotkey: GlobalHotkey? = GlobalHotkey(system: system, action: {})
        hotkey?.register()
        hotkey = nil
        #expect(system.liveHotKeys == 0 && system.liveHandlers == 0)
    }

    @Test func twoHotkeysUseDistinctIDsAndOnlyTheMatchingOneFires() {
        let system = FakeSystem()
        var mainFired = 0, inboxFired = 0
        let main = GlobalHotkey(system: system, action: { mainFired += 1 })
        let inbox = GlobalHotkey(spec: .optionCommandN, id: GlobalHotkey.inboxID, system: system, action: { inboxFired += 1 })
        main.register()
        inbox.register()
        #expect(system.registeredIDs == [GlobalHotkey.mainID, GlobalHotkey.inboxID])
        #expect(GlobalHotkey.mainID != GlobalHotkey.inboxID)
        #expect(inbox.handle(pressedID: GlobalHotkey.mainID) == false)
        #expect(inboxFired == 0)
        #expect(main.handle(pressedID: GlobalHotkey.mainID))
        #expect(mainFired == 1 && inboxFired == 0)
        #expect(inbox.handle(pressedID: GlobalHotkey.inboxID))
        #expect(inboxFired == 1)
    }
}
