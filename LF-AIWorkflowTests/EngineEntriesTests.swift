//
//  EngineEntriesTests.swift
//  LF-AIWorkflowTests
//
//  TD-044 (start at Code, per-task worktree), TD-045 (send findings to Fix), TD-046 (remove worktree).
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(3)))
struct EngineEntriesTests {
    private static let high = Finding(severity: .high, file: "A.swift", line: 3, issue: "Leaks the handle", suggestion: "Close it")

    // MARK: - Transitions

    @Test func queuedToCodeIsAnEdgeAndDoneToFixToo() {
        #expect(TaskTransitions.canMove(from: .queued, to: .code))
        #expect(TaskTransitions.canMove(from: .done, to: .fix))
        #expect(!TaskTransitions.canMove(from: .done, to: .test))
        #expect(!TaskTransitions.canMove(from: .cancelled, to: .fix))
    }

    @Test func doneToFixClearsFinishedAtAndAttempts() throws {
        let done = PreviewFixtures.task("T", state: .done).with(fixAttempts: 2).with(finishedAt: Date())
        let moved = try TaskTransitions.move(done, to: .fix, fixLoopCap: 2)
        #expect(moved.state == .fix && moved.finishedAt == nil && moved.fixAttempts == 0)
    }

    // MARK: - TD-044

    @Test func startAtCodeSkipsThePlanStage() async throws {
        let h = try Harness()
        var draft = h.draft()
        draft.startAtCode = true
        _ = await h.engine.submit(draft)
        #expect(await h.recorder.wait(.done))
        #expect(h.claude.calls(for: .plan).isEmpty)
        #expect(h.claude.calls(for: .code).count == 1)
        #expect(!h.recorder.states.contains(.awaitingApproval))
    }

    @Test func perTaskWorktreeChoiceOverridesTheGlobalSetting() async throws {
        let h = try Harness(settings: Harness.settings(useWorktree: true))
        var draft = h.draft()
        draft.useWorktree = false
        let id = await h.engine.submit(draft)
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(h.worktrees.created.isEmpty)
        #expect(await h.engine.task(id)?.worktree == nil)
    }

    @Test func defaultSettingsDoNotCreateAWorktree() async throws {
        #expect(EngineSettings.default.useWorktree == false)
        let h = try Harness(settings: EngineSettings.default)
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(h.worktrees.created.isEmpty)
        #expect(await h.engine.task(id)?.worktree == nil)
        #expect(await h.engine.task(id)?.baseCommit != nil)
    }

    @Test func noPerTaskChoiceFollowsTheGlobalSetting() async throws {
        let h = try Harness(settings: Harness.settings(useWorktree: true))
        _ = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(h.worktrees.created.count == 1)
    }

    // MARK: - TD-045

    @Test func sendToFixFeedsTheFindingsIntoTheFixPrompt() async throws {
        let h = try Harness()
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        try await h.engine.sendToFix(id, findings: [Self.high])
        #expect(await h.recorder.wait(.done, count: 2))
        let prompts = h.claude.calls(for: .fix).map(\.prompt)
        #expect(prompts.count == 1)
        #expect(prompts[0].contains("Leaks the handle"))
        #expect(await h.engine.task(id)?.state == .done)
    }

    @Test func sendToFixRefusesNonDoneTasksAndEmptyFindings() async throws {
        let h = try Harness()
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        await #expect(throws: WorkflowError.illegalTransition(from: .awaitingApproval, to: .fix)) {
            try await h.engine.sendToFix(id, findings: [Self.high])
        }
        try await h.engine.approvePlan(id)
        #expect(await h.recorder.wait(.done))
        await #expect(throws: WorkflowError.noFindings) { try await h.engine.sendToFix(id, findings: []) }
    }

    // MARK: - TD-046

    @Test func removeWorktreeIsRefusedWhileRunning() async throws {
        let h = try Harness()
        h.claude.script(.code, .hang)
        _ = try await h.runToCodeStart()
        #expect(await h.claude.waitUntilStarted(.code))
        let first = h.recorder.all.first
        let id = try #require(first?.id)
        await #expect(throws: WorkflowError.taskActive(id)) { try await h.engine.removeWorktree(id) }
        #expect(h.worktrees.removed.isEmpty)
        await h.engine.cancel(id)
    }

    @Test func removeWorktreeRemovesItAndClearsTheTaskField() async throws {
        let h = try Harness()
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let current = await h.engine.task(id)
        let path = try #require(current?.worktree?.path)
        try await h.engine.removeWorktree(id)
        #expect(h.worktrees.removed.map(\.path) == [path])
        #expect(await h.engine.task(id)?.worktree == nil)
        await #expect(throws: WorkflowError.noWorktree(id)) { try await h.engine.removeWorktree(id) }
    }

    @Test func removeWorktreeFailureIsReportedAndKeepsTheField() async throws {
        let h = try Harness()
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        h.worktrees.failRemoval(with: .timedOut)
        await #expect(throws: WorkflowError.worktreeRemovalFailed("git timed out.")) {
            try await h.engine.removeWorktree(id)
        }
        #expect(await h.engine.task(id)?.worktree != nil)
    }
}
