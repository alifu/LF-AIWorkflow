//
//  ResearchViewModelCommandTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private actor Recorder: ResearchControlling {
    private(set) var drafts: [ResearchDraft] = []
    private(set) var sent: [Set<Int>] = []
    private(set) var cancelled: [UUID] = []
    let fixedID: UUID
    init(id: UUID = UUID()) { fixedID = id }
    func submit(_ draft: ResearchDraft) -> UUID { drafts.append(draft); return fixedID }
    func send(_ id: UUID, excluded: Set<Int>) { sent.append(excluded) }
    func cancel(_ id: UUID) { cancelled.append(id) }
    func followUp(_ id: UUID, question: String) {}
}

private actor Inbox: ResearchInboxing {
    var stored: [InboxItem]
    private(set) var drained = 0
    init(_ items: [InboxItem]) { stored = items }
    func items() throws -> [InboxItem] { stored }
    func drain() throws -> [InboxItem] { drained += 1; defer { stored = [] }; return stored }
}

@MainActor
struct ResearchViewModelCommandTests {
    private func draft(pages: [CapturedPage] = []) -> ResearchDraft {
        ResearchDraft(question: "Q", output: .summary, deep: false, urls: [URL(string: "https://example.com/")!],
                      inboxPages: pages)
    }

    private func preview(flags: Set<SourceFlag>) -> SourcesPreview {
        let row = SourcesPreviewRow(index: 1, title: "t", host: "h", tokens: 10, tables: 0, flags: flags)
        return SourcesPreview(rows: [row], removedLines: 0, totalTokens: 10)
    }

    private func make(_ recorder: Recorder, inbox: (any ResearchInboxing)? = nil) -> ResearchViewModel {
        ResearchViewModel(updates: AsyncStream<ResearchTask>.makeStream().stream, clock: ManualClock(),
                          controller: recorder, inbox: inbox)
    }

    @Test func previewSubmitsAndReturnsTheId() async {
        let recorder = Recorder()
        let model = make(recorder)
        let id = await model.preview(draft())
        #expect(id == recorder.fixedID)
        #expect(await recorder.drafts.count == 1)
        #expect(await recorder.sent.isEmpty)
    }

    @Test func sendAndCancelForwardToTheController() async {
        let recorder = Recorder()
        let model = make(recorder)
        let id = UUID()
        await model.send(id, excluded: [2])
        await model.cancel(id)
        #expect(await recorder.sent == [[2]])
        #expect(await recorder.cancelled == [id])
    }

    @Test func runAutoSendsWhenNothingIsFlagged() async {
        let recorder = Recorder()
        let model = make(recorder)
        let id = await model.preview(draft(), autoSend: true)
        let task = ResearchTask(id: id!, question: "Q", output: .summary, deep: false, state: .awaitingPreview,
                                preview: preview(flags: []))
        model.receive(task)
        await model.settleCommands()
        #expect(await recorder.sent == [[]])
        #expect(model.estimatedTokens == 10)
    }

    @Test func runDoesNotAutoSendWhenAnySourceIsFlagged() async {
        let recorder = Recorder()
        let model = make(recorder)
        let id = await model.preview(draft(), autoSend: true)
        let task = ResearchTask(id: id!, question: "Q", output: .summary, deep: false, state: .awaitingPreview,
                                preview: preview(flags: [.looksEmpty]))
        model.receive(task)
        await model.settleCommands()
        #expect(await recorder.sent.isEmpty)
    }

    @Test func autoSendHappensOnlyOnce() async {
        let recorder = Recorder()
        let model = make(recorder)
        let id = await model.preview(draft(), autoSend: true)!
        let task = ResearchTask(id: id, question: "Q", output: .summary, deep: false, state: .awaitingPreview,
                                preview: preview(flags: []))
        model.receive(task)
        model.receive(task)
        await model.settleCommands()
        #expect(await recorder.sent.count == 1)
    }

    @Test func addURLValidatesWithHostPolicy() {
        let model = make(Recorder())
        if case .success(let url) = model.addURL("https://Example.com/a#x") { #expect(url.absoluteString == "https://example.com/a") }
        else { Issue.record("expected success") }
        if case .failure = model.addURL("http://10.0.0.1/") {} else { Issue.record("expected blocked") }
        if case .failure(let e) = model.addURL("nonsense") { #expect(e == .invalid) } else { Issue.record("expected invalid") }
    }

    @Test func useInboxReturnsPagesAndUpdatesCount() async {
        let p = CapturedPage(title: "P", url: URL(string: "https://example.com/p")!, text: "x", headings: [],
                             links: [], tables: [], hasPasswordField: false)
        let inbox = Inbox([InboxItem(id: UUID(), page: p)])
        let model = make(Recorder(), inbox: inbox)
        let pages = await model.useInbox()
        #expect(pages == [p])
        #expect(model.inboxCount == 1)
    }

    @Test func submittingInboxPagesDrainsTheInbox() async {
        let p = CapturedPage(title: "P", url: URL(string: "https://example.com/p")!, text: "x", headings: [],
                             links: [], tables: [], hasPasswordField: false)
        let inbox = Inbox([InboxItem(id: UUID(), page: p)])
        let model = make(Recorder(), inbox: inbox)
        _ = await model.preview(draft(pages: [p]))
        #expect(await inbox.drained == 1)
        #expect(model.inboxCount == 0)
    }
}

struct MergedTaskListTests {
    private func research(_ id: UUID, at t: TimeInterval) -> ResearchRowModel {
        ResearchRowModel(id: id, question: "q", state: .done, chips: [], createdAt: Date(timeIntervalSince1970: t),
                         tokensUsed: 0, needsAttention: false, isFinished: true)
    }

    @Test func mergesNewestFirstAcrossKinds() {
        let (a, b) = (UUID(), UUID())
        let items = MergedTaskList.merge(code: [], research: [research(a, at: 1), research(b, at: 5)])
        #expect(items.map(\.id) == [b, a])
    }

    @Test func emptyInputsGiveEmptyList() {
        #expect(MergedTaskList.merge(code: [], research: []).isEmpty)
    }
}
