//
//  ResearchComposerViewModelTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private struct TabsSafari: SafariControlling {
    var list: [SafariTab]
    var state: SafariPermissionState = .granted
    var failure: SafariError?

    func tabs() async throws(SafariError) -> [SafariTab] {
        if let failure { throw failure }
        return list
    }
    func currentTab() async throws(SafariError) -> SafariTab? { list.first { $0.current } }
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage { throw .tabChanged }
    func permission() async -> SafariPermissionState { state }
}

private actor RecordingController: ResearchControlling {
    private(set) var drafts: [ResearchDraft] = []
    private(set) var sent: [(UUID, Set<Int>)] = []
    private(set) var cancelled: [UUID] = []
    let fixedID = UUID()

    func submit(_ draft: ResearchDraft) -> UUID { drafts.append(draft); return fixedID }
    func send(_ id: UUID, excluded: Set<Int>) { sent.append((id, excluded)) }
    func cancel(_ id: UUID) { cancelled.append(id) }
    func followUp(_ id: UUID, question: String) {}
}

private actor StubInbox: ResearchInboxing {
    var stored: [InboxItem]
    private(set) var drained = 0
    init(_ items: [InboxItem] = []) { stored = items }
    func items() throws -> [InboxItem] { stored }
    func drain() throws -> [InboxItem] { drained += 1; defer { stored = [] }; return stored }
}

private func tab(_ n: Int, current: Bool = false) -> SafariTab {
    SafariTab(window: 1, tab: n, title: "T\(n)", url: URL(string: "https://example.com/\(n)")!, current: current)
}

private func page(_ n: Int) -> CapturedPage {
    CapturedPage(title: "P\(n)", url: URL(string: "https://example.com/p\(n)")!, text: "text \(n)",
                 headings: [], links: [], tables: [], hasPasswordField: false)
}

@MainActor
struct ResearchComposerViewModelTests {
    private func make(tabs: [SafariTab] = [], controller: RecordingController = RecordingController(),
                      inbox: (any ResearchInboxing)? = nil, safari: TabsSafari? = nil)
        -> (ResearchComposerViewModel, ResearchViewModel, RecordingController) {
        let research = ResearchViewModel(updates: AsyncStream<ResearchTask>.makeStream().stream,
                                         clock: ManualClock(), controller: controller, inbox: inbox)
        let composer = ResearchComposerViewModel(safari: safari ?? TabsSafari(list: tabs), research: research)
        return (composer, research, controller)
    }

    @Test func emptyQuestionIsRejected() {
        let (composer, _, _) = make()
        composer.urlInput = "https://example.com/a"
        composer.addURL()
        composer.question = "   \n"
        #expect(composer.issue == .emptyQuestion)
        #expect(composer.draft() == nil)
    }

    @Test func noSourcesIsRejected() {
        let (composer, _, _) = make()
        composer.question = "Which is faster?"
        #expect(composer.issue == .noSources)
    }

    @Test func blockedAndMalformedURLsShowInlineErrorAndAreNotAdded() {
        let (composer, _, _) = make()
        composer.urlInput = "http://127.0.0.1/admin"
        composer.addURL()
        #expect(composer.urls.isEmpty)
        #expect(composer.urlError != nil)
        composer.urlInput = "not a url"
        composer.addURL()
        #expect(composer.urls.isEmpty)
        #expect(composer.urlError != nil)
    }

    @Test func validURLIsNormalizedAddedDedupedAndClearsInput() {
        let (composer, _, _) = make()
        composer.urlInput = "https://Example.com/a#frag"
        composer.addURL()
        composer.urlInput = "https://example.com/a"
        composer.addURL()
        #expect(composer.urls == [URL(string: "https://example.com/a")!])
        #expect(composer.urlError == nil)
        #expect(composer.urlInput.isEmpty)
    }

    @Test func depthAndPageLimitsClamp() {
        let (composer, _, _) = make()
        composer.setDepth(9); #expect(composer.depth == 2)
        composer.setDepth(-3); #expect(composer.depth == 0)
        composer.setMaxPages(500); #expect(composer.maxPages == 50)
        composer.setMaxPages(0); #expect(composer.maxPages == 1)
    }

    @Test func onlyTheCurrentTabIsPreTickedOnFirstLoad() async {
        let (composer, _, _) = make(tabs: [tab(1), tab(2, current: true), tab(3)])
        await composer.refreshTabs()
        #expect(composer.tabs.map(\.selected) == [false, true, false])
    }

    @Test func tickingSurvivesTabListRefreshByURL() async {
        let (composer, _, _) = make(tabs: [tab(1), tab(2, current: true)])
        await composer.refreshTabs()
        composer.toggle(composer.tabs[0].id)
        composer.toggle(composer.tabs[1].id)
        #expect(composer.tabs.map(\.selected) == [true, false])
        await composer.refreshTabs()
        #expect(composer.tabs.map(\.selected) == [true, false])
    }

    @Test func draftCarriesSelectionsAndClampedLimits() async throws {
        let (composer, _, _) = make(tabs: [tab(1, current: true)])
        await composer.refreshTabs()
        composer.question = "  Compare  "
        composer.deep = true
        composer.output = .comparison
        composer.setDepth(1)
        composer.setMaxPages(7)
        composer.urlInput = "https://example.com/z"
        composer.addURL()
        let draft = try #require(composer.draft())
        #expect(draft.question == "Compare")
        #expect(draft.tabs.count == 1 && draft.urls.count == 1)
        #expect(draft.deep && draft.output == .comparison)
        #expect(draft.limits.depth == 1 && draft.limits.maxPages == 7 && draft.limits.sameSiteOnly)
    }

    @Test func inboxPagesCountAsASourceAndAreClearedByUseInbox() async {
        let inbox = StubInbox([InboxItem(id: UUID(), page: page(1)), InboxItem(id: UUID(), page: page(2))])
        let (composer, research, _) = make(inbox: inbox)
        await composer.useInbox()
        #expect(composer.inboxPages.count == 2)
        #expect(research.inboxCount == 2)
        composer.question = "Q"
        #expect(composer.issue == nil)
    }

    @Test func submitPreviewSendsDraftThroughTheController() async {
        let (composer, _, controller) = make()
        composer.question = "Q"
        composer.urlInput = "https://example.com/a"
        composer.addURL()
        await composer.submit(run: false)
        #expect(await controller.drafts.count == 1)
    }

    @Test func submitIsANoOpWhenInvalid() async {
        let (composer, _, controller) = make()
        await composer.submit(run: true)
        #expect(await controller.drafts.isEmpty)
    }

    @Test func setupGuideFollowsPermissionState() {
        #expect(SafariSetupGuide.make(state: .granted, error: nil) == nil)
        let denied = SafariSetupGuide.make(state: .denied, error: nil)
        #expect(denied?.showsOpenSettings == true)
        #expect(denied?.steps.isEmpty == false)
        #expect(denied?.fallback.contains("public URLs") == true)
        let js = SafariSetupGuide.make(state: .granted, error: .javascriptFromAppleEventsOff)
        #expect(js?.title.contains("JavaScript") == true)
        let notRunning = SafariSetupGuide.make(state: .safariNotRunning, error: nil)
        #expect(notRunning?.showsOpenSettings == false)
        #expect(SafariSetupGuide.settingsURL.absoluteString.contains("Privacy_Automation"))
    }

    @Test func refreshTabsRecordsPermissionAndError() async {
        let safari = TabsSafari(list: [], state: .denied, failure: .automationDenied)
        let (composer, research, _) = make(safari: safari)
        await composer.refreshTabs()
        #expect(research.safariState == .denied)
        #expect(composer.safariError == .automationDenied)
        #expect(composer.setupGuide != nil)
    }
}
