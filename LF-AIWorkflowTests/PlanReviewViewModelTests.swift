//
//  PlanReviewViewModelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@MainActor
final class SpyEditor: EditorOpening {
    struct Call: Equatable { let path: String; let line: Int?; let root: URL }
    private(set) var calls: [Call] = []
    private(set) var revealed: [URL] = []
    var result = true
    func open(path: String, line: Int?, within root: URL) -> Bool { calls.append(Call(path: path, line: line, root: root)); return result }
    func reveal(_ url: URL) { revealed.append(url) }
}

@MainActor
final class SpyPasteboard: Pasteboarding {
    private(set) var copied: [String] = []
    func copy(_ string: String) { copied.append(string) }
}

@MainActor
final class SpyDecider: TaskDeciding {
    private(set) var approved: [UUID] = []
    private(set) var cancelled: [UUID] = []
    func approve(_ id: UUID) async { approved.append(id) }
    func cancel(_ id: UUID) async { cancelled.append(id) }
}

struct StubPlanLoader: PlanLoading {
    var document: PlanDocument?
    func load(_ url: URL) async throws -> PlanDocument {
        guard let document else { throw CocoaError(.fileNoSuchFile) }
        return document
    }
}

struct StubReviewLoader: ReviewLoading {
    var report: ReviewReport?
    func load(_ url: URL) async throws -> ReviewReport {
        guard let report else { throw CocoaError(.fileNoSuchFile) }
        return report
    }
}

private let planURL = URL(fileURLWithPath: "/tmp/MyApp/.claude/plans/login.md")
private let planDoc = PlanDocument(path: planURL, steps: ["A", "B", "C"], estimatedTokens: 1_200, isTruncated: false)

@MainActor
@Suite struct ReviewViewModelTests {
    private let finds = [
        Finding(severity: .low, file: "z.swift", line: 1, issue: "l", suggestion: nil),
        Finding(severity: .high, file: "Theme.kt", line: 31, issue: "h", suggestion: "s"),
        Finding(severity: .high, file: "A.kt", line: 2, issue: "h2", suggestion: nil),
        Finding(severity: .medium, file: "m.kt", line: nil, issue: "m", suggestion: nil),
    ]
    private let reviewURL = URL(fileURLWithPath: "/tmp/MyApp/.claude/reviews/login.md")

    private func make(report: ReviewReport?, review: URL? = URL(fileURLWithPath: "/tmp/MyApp/.claude/reviews/login.md"),
                      editor: SpyEditor = SpyEditor()) -> (ReviewViewModel, SpyEditor) {
        let task = PreviewFixtures.task("Login", state: .done, reviewFile: review, worktree: true)
        return (ReviewViewModel(task: task, loader: StubReviewLoader(report: report), opener: editor), editor)
    }

    @Test func loadsFindingsSortedWithCounts() async {
        let (vm, _) = make(report: ReviewReport(findings: finds, unparsedLineCount: 1))
        await vm.load()
        #expect(vm.findings.map(\.file) == ["A.kt", "Theme.kt", "m.kt", "z.swift"])
        #expect(vm.countsBySeverity == [.high: 2, .medium: 1, .low: 1])
        #expect(vm.unparsedCount == 1)
        #expect(vm.isLoaded)
        #expect(vm.reportPath == "/tmp/MyApp/.claude/reviews/login.md")
    }

    @Test func missingFileSetsAMessage() async {
        let (vm, _) = make(report: nil)
        await vm.load()
        #expect(vm.findings.isEmpty)
        #expect(vm.message?.contains("login.md") == true)
    }

    @Test func noReviewFileSetsAMessage() async {
        let (vm, _) = make(report: ReviewReport(findings: finds, unparsedLineCount: 0), review: nil)
        await vm.load()
        #expect(vm.findings.isEmpty)
        #expect(vm.message != nil)
    }

    @Test func openRoutesToTheOpenerWithinTheWorkingDirectory() async {
        let (vm, editor) = make(report: ReviewReport(findings: finds, unparsedLineCount: 0))
        await vm.load()
        vm.open(vm.findings[1])
        #expect(editor.calls.count == 1)
        #expect(editor.calls[0].path == "Theme.kt")
        #expect(editor.calls[0].line == 31)
        #expect(editor.calls[0].root.path.contains(".wt"))   // the worktree, not the project root
        #expect(vm.message == nil)
    }

    @Test func refusedOpenShowsAMessage() async {
        let editor = SpyEditor()
        editor.result = false
        let (vm, _) = make(report: ReviewReport(findings: [Finding(severity: .high, file: "../../.ssh/config", line: 1, issue: "x", suggestion: nil)],
                                                unparsedLineCount: 0), editor: editor)
        await vm.load()
        vm.open(vm.findings[0])
        #expect(vm.message?.contains("../../.ssh/config") == true)
    }

    @Test func openWorktreeRevealsTheWorkingDirectory() {
        let (vm, editor) = make(report: nil)
        vm.openWorktree()
        #expect(editor.revealed.count == 1)
        #expect(editor.revealed[0].path.contains(".wt"))
    }

    @Test func sendHighToFixIsDisabled() {
        let (vm, _) = make(report: nil)
        #expect(!vm.canSendHighToFix)
    }
}

@MainActor
@Suite struct PlanApprovalViewModelTests {
    private func make(doc: PlanDocument? = planDoc, plan: URL? = planURL) -> (PlanApprovalViewModel, SpyEditor, SpyDecider, WorkflowTask) {
        let task = PreviewFixtures.task("Login", state: .awaitingApproval, planFile: plan)
        let editor = SpyEditor(), decider = SpyDecider()
        return (PlanApprovalViewModel(task: task, loader: StubPlanLoader(document: doc), opener: editor, decider: decider),
                editor, decider, task)
    }

    @Test func loadExposesTheDocument() async {
        let (vm, _, _, _) = make()
        await vm.load()
        #expect(vm.document == planDoc)
        #expect(vm.loadError == nil)
        #expect(vm.canAct)
    }

    @Test func loadFailureShowsTheErrorWithThePath() async {
        let (vm, _, _, _) = make(doc: nil)
        await vm.load()
        #expect(vm.document == nil)
        #expect(vm.loadError?.contains("login.md") == true)
        #expect(vm.canAct)   // approving without a readable plan is still the user's call
    }

    @Test func approveRoutesOnce() async {
        let (vm, _, decider, task) = make()
        await vm.approve()
        await vm.approve()
        await vm.cancelTask()
        #expect(decider.approved == [task.id])
        #expect(decider.cancelled.isEmpty)
        #expect(!vm.canAct)
    }

    @Test func cancelRoutesOnceAndDisablesApprove() async {
        let (vm, _, decider, task) = make()
        await vm.cancelTask()
        await vm.approve()
        #expect(decider.cancelled == [task.id])
        #expect(decider.approved.isEmpty)
    }

    @Test func openInEditorUsesThePlanPathInsideTheWorkingDirectory() {
        let (vm, editor, _, task) = make()
        vm.openInEditor()
        #expect(editor.calls == [SpyEditor.Call(path: planURL.path, line: nil, root: task.workingDirectory)])
    }

    @Test func refusedOpenShowsAnError() {
        let (vm, editor, _, _) = make()
        editor.result = false
        vm.openInEditor()
        #expect(vm.openError != nil)
    }

    @Test func noPlanFileMeansNothingToOpen() {
        let (vm, editor, _, _) = make(plan: nil)
        vm.openInEditor()
        #expect(editor.calls.isEmpty)
    }
}

@MainActor
@Suite struct PlanViewModelTests {
    private func make(state: TaskState, plan: URL? = planURL, doc: PlanDocument? = planDoc,
                      resume: TaskState? = nil) -> (PlanViewModel, SpyEditor, SpyPasteboard) {
        let task = PreviewFixtures.task("Login", state: state, planFile: plan, wait: resume == nil ? nil : .noTestCommand, resume: resume)
        let editor = SpyEditor(), board = SpyPasteboard()
        return (PlanViewModel(task: task, loader: StubPlanLoader(document: doc), opener: editor, pasteboard: board), editor, board)
    }

    @Test func badgePerState() {
        for state in [TaskState.queued, .plan, .awaitingApproval] {
            #expect(make(state: state).0.badge == .waiting, "\(state)")
        }
        for state in [TaskState.code, .test, .fix, .review, .done, .failed, .cancelled] {
            #expect(make(state: state).0.badge == .approved, "\(state)")
        }
    }

    @Test func parkedBeforeApprovalIsWaiting() {
        #expect(make(state: .awaitingInput, resume: .plan).0.badge == .waiting)
        #expect(make(state: .awaitingInput, resume: .test).0.badge == .approved)
    }

    @Test func hiddenWithoutAPlanFile() {
        #expect(make(state: .code, plan: nil).0.isVisible == false)
        #expect(make(state: .done).0.isVisible)
    }

    @Test func badgeAccessibilityText() {
        #expect(PlanBadge.approved.accessibilityText == "Approved")
        #expect(PlanBadge.waiting.accessibilityText == "Waiting for approval")
    }

    @Test func loadAndPath() async {
        let (vm, _, _) = make(state: .done)
        await vm.load()
        #expect(vm.document?.steps == ["A", "B", "C"])
        #expect(vm.pathText == planURL.path)
    }

    @Test func missingFileGivesInlineErrorWithPath() async {
        let (vm, _, _) = make(state: .done, doc: nil)
        await vm.load()
        #expect(vm.document == nil)
        #expect(vm.loadError?.contains(planURL.path) == true)
    }

    @Test func copyPathWritesThePathToThePasteboard() {
        let (vm, _, board) = make(state: .done)
        vm.copyPath()
        #expect(board.copied == [planURL.path])
        #expect(vm.didCopy)
    }

    @Test func openInEditorGoesThroughTheOpener() {
        let (vm, editor, _) = make(state: .done)
        vm.openInEditor()
        #expect(editor.calls.map(\.path) == [planURL.path])
    }

    @Test func hiddenViewDoesNothing() async {
        let (vm, editor, board) = make(state: .code, plan: nil)
        await vm.load()
        vm.openInEditor(); vm.copyPath()
        #expect(editor.calls.isEmpty && board.copied.isEmpty && vm.document == nil)
    }
}
