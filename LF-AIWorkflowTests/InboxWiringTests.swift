//
//  InboxWiringTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private struct TabSafari: SafariControlling {
    var tab: SafariTab?
    var page: CapturedPage?
    var failure: SafariError?

    func tabs() async throws(SafariError) -> [SafariTab] { tab.map { [$0] } ?? [] }
    func currentTab() async throws(SafariError) -> SafariTab? {
        if let failure { throw failure }
        return tab
    }
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage {
        guard let page else { throw .malformedOutput }
        return page
    }
    func permission() async -> SafariPermissionState { .granted }
}

private actor CountingInbox: ResearchInboxAdding {
    var results: [InboxResult]
    private(set) var added: [CapturedPage] = []
    init(results: [InboxResult]) { self.results = results }
    func add(_ page: CapturedPage) throws -> InboxResult {
        added.append(page)
        return results.removeFirst()
    }
}

private final class FakeRegistrar: HotkeyRegistering {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    func register() -> Bool { true }
    func unregister() {}
}

@MainActor
struct InboxWiringTests {
    private let url = URL(string: "https://a.example/x")!

    private func page(password: Bool = false) -> CapturedPage {
        CapturedPage(title: "T", url: url, text: "body", headings: [], links: [], tables: [], hasPasswordField: password)
    }

    private var tab: SafariTab { SafariTab(window: 1, tab: 1, title: "T", url: url, current: true) }

    @Test func inboxHotkeyDefaultsToControlOptionCommandC() {
        let store = SettingsStore(suiteName: "lf-inbox-\(UUID().uuidString)")
        #expect(store.inboxHotkey == .controlOptionCommandC)
        #expect(store.inboxHotkey.displayString == "⌃⌥⌘C")
    }

    @Test func inboxHotkeyPersistsAcrossStores() {
        let suite = "lf-inbox-\(UUID().uuidString)"
        SettingsStore(suiteName: suite).inboxHotkey = .controlOptionSpace
        #expect(SettingsStore(suiteName: suite).inboxHotkey == .controlOptionSpace)
    }

    @Test func invalidOrClashingStoredInboxHotkeyFallsBackToDefault() throws {
        let suite = "lf-inbox-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(try JSONEncoder().encode(HotkeySpec(keyCode: 8, modifiers: 0)), forKey: SettingsStore.Keys.inboxHotkey)
        #expect(SettingsStore(suiteName: suite).inboxHotkey == .controlOptionCommandC)
        defaults.set(try JSONEncoder().encode(HotkeySpec.default), forKey: SettingsStore.Keys.inboxHotkey)
        #expect(SettingsStore(suiteName: suite).inboxHotkey == .controlOptionCommandC)
    }

    @Test func researchRootDefaultsToDocumentsFolderAndHonorsAbsoluteSetting() {
        let suite = "lf-inbox-\(UUID().uuidString)"
        let store = SettingsStore(suiteName: suite)
        #expect(store.researchRoot.path.hasSuffix("/Documents/LF-AIWorkflow/Research"))
        store.researchRootPath = "/tmp/research-root"
        #expect(SettingsStore(suiteName: suite).researchRoot.path == "/tmp/research-root")
        store.researchRootPath = "relative/path"
        #expect(store.researchRoot.path.hasSuffix("/Documents/LF-AIWorkflow/Research"))
    }

    @Test func captureSavesCurrentTabAndReportsCount() async {
        let inbox = CountingInbox(results: [.added(count: 3)])
        let outcome = await InboxCapture(safari: TabSafari(tab: tab, page: page()), inbox: inbox).capture()
        #expect(outcome == InboxCaptureOutcome(message: "Saved to inbox (3)", count: 3))
        #expect(await inbox.added.count == 1)
    }

    @Test func captureReportsDuplicateNoTabPasswordPageAndSafariErrors() async {
        let dup = CountingInbox(results: [.duplicate])
        #expect(await InboxCapture(safari: TabSafari(tab: tab, page: page()), inbox: dup).capture().message == "Already in the inbox")
        let none = CountingInbox(results: [])
        #expect(await InboxCapture(safari: TabSafari(), inbox: none).capture().message == "No Safari tab to save")
        let secret = await InboxCapture(safari: TabSafari(tab: tab, page: page(password: true)), inbox: none).capture()
        #expect(secret.count == nil)
        #expect(await none.added.isEmpty)
        let denied = await InboxCapture(safari: TabSafari(failure: .automationDenied), inbox: none).capture()
        #expect(denied.message.contains("control Safari"))
    }

    @Test func inboxHotkeyManagerRunsTheCaptureActionIndependentlyOfTheMainOne() {
        var main = 0, inbox = 0
        var registrars: [FakeRegistrar] = []
        func manager(_ action: @escaping () -> Void) -> HotkeyManager {
            HotkeyManager(factory: { _, act in
                let r = FakeRegistrar(action: act); registrars.append(r); return r
            }, action: action)
        }
        let mainManager = manager { main += 1 }
        let inboxManager = manager { inbox += 1 }
        #expect(mainManager.apply(.default))
        #expect(inboxManager.apply(.controlOptionCommandC))
        registrars[1].action()
        #expect((main, inbox) == (0, 1))
        #expect(GlobalHotkey.mainID != GlobalHotkey.inboxID)
    }
}
