//
//  WorkflowModelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct WorkflowModelTests {
    static func makeTask() -> WorkflowTask {
        WorkflowTask(id: UUID(), title: "T", slug: "t", prompt: "p", projectRoot: URL(fileURLWithPath: "/repo"),
                     documents: [], skillDirs: [], state: .queued, resumeState: nil, waitReason: nil, failure: nil,
                     worktree: nil, sessionId: nil, planFile: nil, fixAttempts: 0, usageByStage: [:],
                     lastErrors: nil, testCommandDisplay: nil, reviewFile: nil, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func stageHasFourCases() { #expect(WorkflowStage.allCases.count == 4) }

    @Test func displayNames() {
        #expect(WorkflowStage.allCases.map(\.displayName) == ["Plan", "Code", "Fix", "Review"])
    }

    @Test func claudeStageMapping() {
        let expected: [TaskState: WorkflowStage?] = [
            .queued: nil, .plan: .plan, .awaitingApproval: nil, .code: .code, .test: nil, .fix: .fix,
            .review: .review, .done: nil, .failed: nil, .cancelled: nil, .awaitingInput: nil,
        ]
        #expect(TaskState.allCases.count == 11)
        for state in TaskState.allCases { #expect(state.claudeStage == expected[state]!) }
    }

    @Test func terminalStates() {
        let terminal = Set(TaskState.allCases.filter(\.isTerminal))
        #expect(terminal == [.done, .failed, .cancelled])
    }

    @Test func withStateReturnsCopy() {
        let original = Self.makeTask()
        let changed = original.with(state: .plan)
        #expect(changed.state == .plan)
        #expect(original.state == .queued)
        #expect(changed.id == original.id)
    }

    @Test func withersChangeOnlyTheirField() {
        let t = Self.makeTask()
        let wt = Worktree(path: URL(fileURLWithPath: "/wt"), branch: "ai/t", baseCommit: "abc")
        #expect(t.with(worktree: wt).worktree == wt)
        #expect(t.with(sessionId: "s").sessionId == "s")
        #expect(t.with(fixAttempts: 2).fixAttempts == 2)
        #expect(t.with(lastErrors: "e").lastErrors == "e")
        #expect(t.with(failure: .spawn("x")).failure == .spawn("x"))
        #expect(t.with(planFile: URL(fileURLWithPath: "/p.md")).planFile?.path == "/p.md")
        #expect(t.with(reviewFile: URL(fileURLWithPath: "/r.md")).reviewFile?.path == "/r.md")
        let waiting = t.with(waiting: .noTestCommand, resume: .test)
        #expect(waiting.waitReason == .noTestCommand)
        #expect(waiting.resumeState == .test)
        #expect(t.waitReason == nil)
        #expect(t.with(sessionId: "s").with(state: .code).sessionId == "s")
    }

    @Test func totalUsageSumsStages() {
        let a = TokenUsage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
        let b = TokenUsage(input: 10, output: 20, cacheRead: 30, cacheCreation: 40)
        let t = Self.makeTask().adding(usage: a, for: .plan).adding(usage: b, for: .code)
        #expect(t.totalUsage == a + b)
        let again = t.adding(usage: a, for: .plan)
        #expect(again.usageByStage[.plan] == a + a)
        #expect(t.usageByStage[.plan] == a)
    }

    @Test func workingDirectoryPrefersWorktree() {
        let t = Self.makeTask()
        #expect(t.workingDirectory.path == "/repo")
        let wt = Worktree(path: URL(fileURLWithPath: "/wt"), branch: "b", baseCommit: "c")
        #expect(t.with(worktree: wt).workingDirectory.path == "/wt")
    }
}
