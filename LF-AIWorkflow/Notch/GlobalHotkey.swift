//
//  GlobalHotkey.swift
//  LF-AIWorkflow
//

import Carbon.HIToolbox

/// Seam so the app wiring can be tested without Carbon.
protocol HotkeyRegistering: AnyObject {
    @discardableResult func register() -> Bool
    func unregister()
}

/// The Carbon calls `GlobalHotkey` needs, behind a seam so register/unregister pairing is testable.
protocol HotkeySystem: AnyObject {
    /// Installs the hotkey-pressed handler; `owner` is passed back to the callback. Nil when refused.
    func installHandler(owner: UnsafeMutableRawPointer) -> EventHandlerRef?
    /// Registers the key combination. Nil when refused (for example already taken).
    func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef?
    func unregisterHotKey(_ ref: EventHotKeyRef)
    func removeHandler(_ ref: EventHandlerRef)
}

/// Production seam over Carbon `InstallEventHandler` / `RegisterEventHotKey`.
final class CarbonHotkeySystem: HotkeySystem {
    private static let signature: OSType = 0x4C46_484B   // 'LFHK'

    /// Complexity: O(1) time, O(1) space
    func installHandler(owner: UnsafeMutableRawPointer) -> EventHandlerRef? {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), globalHotkeyCallback, 1, &spec, owner, &ref)
        return status == noErr ? ref : nil
    }

    /// Complexity: O(1) time, O(1) space
    func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }

    func unregisterHotKey(_ ref: EventHotKeyRef) { UnregisterEventHotKey(ref) }
    func removeHandler(_ ref: EventHandlerRef) { RemoveEventHandler(ref) }
}

/// System-wide hotkey through Carbon `RegisterEventHotKey` (no Accessibility permission needed).
/// Every successful `register()` is paired with one `unregister()` (explicit or in `deinit`).
final class GlobalHotkey: HotkeyRegistering {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private let system: any HotkeySystem
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(spec: HotkeySpec = .default, system: any HotkeySystem = CarbonHotkeySystem(), action: @escaping () -> Void) {
        self.keyCode = spec.keyCode
        self.modifiers = spec.modifiers
        self.system = system
        self.action = action
    }

    isolated deinit { unregister() }

    /// Returns false when the system refuses (for example the combination is taken); nothing stays installed then.
    /// Complexity: O(1) time, O(1) space
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        guard let handler = system.installHandler(owner: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        handlerRef = handler
        guard let hotKey = system.registerHotKey(keyCode: keyCode, modifiers: modifiers) else {
            unregister()
            return false
        }
        hotKeyRef = hotKey
        return true
    }

    /// Complexity: O(1) time, O(1) space
    func unregister() {
        if let hotKeyRef { system.unregisterHotKey(hotKeyRef) }
        if let handlerRef { system.removeHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    fileprivate func fire() { action() }
}

/// Carbon delivers hotkey events on the main thread.
private nonisolated func globalHotkeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkey.fire() }
    return noErr
}
