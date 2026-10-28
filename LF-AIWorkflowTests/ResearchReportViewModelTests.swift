//
//  ResearchReportViewModelTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private actor FollowRecorder: ResearchControlling {
    private(set) var asked: [(UUID, String)] = []
    private(set) var sent: [(UUID, Set<Int>)] = []
    func submit(_ draft: ResearchDraft) -> UUID { UUID() }
    func send(_ id: UUID, excluded: Set<Int>) { sent.append((id, excluded)) }
    func cancel(_ id: UUID) {}
    func followUp(_ id: UUID, question: String) { asked.append((id, question)) }
}

private let sampleReport = """
Answer [1].

| Name | Price |
|---|---|
| =EVIL() | 5, ok |

## Sources

1. [A](https://a.example)
"""

@MainActor
struct ResearchReportViewModelTests {
    private func make(state: ResearchState = .done, folder: URL? = nil, text: String? = sampleReport,
                      controller: FollowRecorder = FollowRecorder(), opener: SpyURLOpener = SpyURLOpener(),
                      preview: SourcesPreview? = nil) -> (ResearchReportViewModel, FollowRecorder, SpyURLOpener) {
        let report = URL(fileURLWithPath: "/tmp/r/report.md")
        let task = ResearchTask(question: "q", output: .summary, deep: false, state: state,
                                folder: folder.map(ResearchFolder.init(url:)), preview: preview, reportFile: report)
        let vm = ResearchReportViewModel(task: task, controller: controller, opener: EditorOpener(backend: opener),
                                         readReport: { _ in text })
        return (vm, controller, opener)
    }

    @Test func parsesTableFromReportFileNotRawMarkdown() async {
        let (vm, _, _) = make()
        await vm.loadReport()
        #expect(vm.report?.table?.header == ["Name", "Price"])
    }

    @Test func csvExportIsFormulaGuardedAndQuoted() async {
        let (vm, _, _) = make()
        await vm.loadReport()
        #expect(vm.csvDocument() == "Name,Price\r\n'=EVIL(),\"5, ok\"\r\n")
    }

    @Test func noCSVWhenThereIsNoTable() async {
        let (vm, _, _) = make(text: "Just prose.")
        await vm.loadReport()
        #expect(vm.csvDocument() == nil)
    }

    @Test func exportWritesTheGuardedCSV() async throws {
        let (vm, _, _) = make()
        await vm.loadReport()
        let dest = try TestEnv.makeTempDir().appendingPathComponent("out.csv")
        try vm.exportCSV(to: dest)
        #expect(try String(contentsOf: dest, encoding: .utf8).hasPrefix("Name,Price"))
    }

    @Test func followUpDisabledWhileRunningOrEmpty() {
        let (running, _, _) = make(state: .analyze)
        running.followUpText = "more?"
        #expect(!running.canAsk)
        let (done, _, _) = make()
        #expect(!done.canAsk)
        done.followUpText = "  more?  "
        #expect(done.canAsk)
    }

    @Test func askSendsTrimmedQuestionAndClears() async {
        let (vm, controller, _) = make()
        vm.followUpText = "  why?  "
        await vm.ask()
        #expect(await controller.asked.map(\.1) == ["why?"])
        #expect(vm.followUpText.isEmpty)
    }

    @Test func askIgnoredWhenDisabled() async {
        let (vm, controller, _) = make(state: .analyze)
        vm.followUpText = "why?"
        await vm.ask()
        #expect(await controller.asked.isEmpty)
    }

    @Test func exclusionsArePassedToSend() async {
        let (vm, controller, _) = make(state: .awaitingPreview)
        vm.toggle(2)
        vm.toggle(3)
        vm.toggle(3)
        await vm.sendSelected()
        #expect(await controller.sent.map(\.1) == [[2]])
    }

    @Test func openFolderRevealsOnlyTheTaskFolder() throws {
        let dir = try TestEnv.makeTempDir()
        let (vm, _, spy) = make(folder: dir)
        #expect(vm.openFolder())
        #expect(spy.revealed == [dir])
        #expect(spy.opened.isEmpty)
    }

    @Test func openFolderRefusesMissingFolder() {
        let (vm, _, spy) = make(folder: URL(fileURLWithPath: "/nonexistent/lf-xyz"))
        #expect(!vm.openFolder())
        #expect(spy.revealed.isEmpty)
        let (none, _, _) = make()
        #expect(!none.openFolder())
    }

    @Test func linkConfirmationNamesHostOnlyForHTTP() {
        #expect(ResearchReportViewModel.confirmationHost(for: URL(string: "https://Docs.Example.com/x")!) == "docs.example.com")
        #expect(ResearchReportViewModel.confirmationHost(for: URL(string: "file:///etc/passwd")!) == nil)
        #expect(ResearchReportViewModel.confirmationHost(for: URL(string: "javascript:1")!) == nil)
    }
}
