//
//  TaskBoardTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct TaskBoardTests {
    private let t0 = PreviewFixtures.epoch
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func rows(_ board: TaskBoard, now: Date? = nil) -> [TaskRowModel] {
        board.rows(now: now ?? at(600), fixLoopCap: 2)
    }

    // MARK: ordering and hiding

    @Test func attentionFirstThenNewest() {
        var board = TaskBoard()
        let old = PreviewFixtures.task("old", state: .code, created: at(0))
        let new = PreviewFixtures.task("new", state: .code, created: at(10))
        let wait = PreviewFixtures.task("approve me", state: .awaitingApproval, created: at(5))
        for t in [old, new, wait] { _ = board.apply(t, now: at(20)) }
        #expect(rows(board).map(\.title) == ["approve me", "new", "old"])
    }

    @Test func clearDoneHidesFinishedButNotRunning() {
        var board = TaskBoard()
        let running = PreviewFixtures.task("run", state: .code)
        let done = PreviewFixtures.task("done", state: .done)
        let failed = PreviewFixtures.task("failed", state: .failed)
        let cancelled = PreviewFixtures.task("cancelled", state: .cancelled)
        let parked = PreviewFixtures.task("parked", state: .awaitingApproval)
        for t in [running, done, failed, cancelled, parked] { _ = board.apply(t, now: at(1)) }
        board.clearDone()
        #expect(Set(rows(board).map(\.title)) == ["run", "parked"])
        #expect(board.task(done.id) != nil)
    }

    @Test func laterUpdateReplacesTheSnapshot() {
        var board = TaskBoard()
        let id = UUID()
        _ = board.apply(PreviewFixtures.task(state: .plan, id: id), now: at(1))
        _ = board.apply(PreviewFixtures.task(state: .code, id: id), now: at(2))
        #expect(rows(board).count == 1 && rows(board).first?.state == .code)
    }

    @Test func elapsedFreezesWhenTheTaskFinishes() {
        var board = TaskBoard()
        let id = UUID()
        _ = board.apply(PreviewFixtures.task(state: .code, id: id), now: at(30))
        _ = board.apply(PreviewFixtures.task(state: .done, id: id), now: at(90))
        #expect(rows(board, now: at(9_999)).first?.elapsed == .seconds(90))
    }

    // MARK: summary

    @Test func summaryCountsRunningOnly() {
        var board = TaskBoard()
        let states: [TaskState] = [.code, .test, .awaitingApproval, .done, .queued, .awaitingInput]
        for (i, s) in states.enumerated() { _ = board.apply(PreviewFixtures.task("t\(i)", state: s, created: at(Double(i))), now: at(50)) }
        let summary = board.summary()
        #expect(summary.activeCount == 2)
        #expect(summary.attentionCount == 2)
    }

    @Test func summaryLeadsWithTheNewestRunningStep() {
        var board = TaskBoard()
        _ = board.apply(PreviewFixtures.task("a", state: .plan, created: at(0)), now: at(1))
        _ = board.apply(PreviewFixtures.task("b", state: .code, created: at(5)), now: at(6))
        let summary = board.summary()
        #expect(summary.leadStep == .code)
        #expect(summary.accessibilityLabel == "2 tasks running, Code stage")
    }

    @Test func summaryLabels() {
        #expect(CollapsedSummary(activeCount: 0, leadStep: nil, attentionCount: 0).accessibilityLabel == "No active tasks")
        #expect(CollapsedSummary(activeCount: 1, leadStep: .test, attentionCount: 0).accessibilityLabel == "1 task running, Test stage")
        #expect(CollapsedSummary(activeCount: 0, leadStep: nil, attentionCount: 1).accessibilityLabel
                == "No active tasks, 1 needs attention")
        #expect(CollapsedSummary(activeCount: 2, leadStep: .fix, attentionCount: 2).accessibilityLabel
                == "2 tasks running, Fix stage, 2 need attention")
    }

    // MARK: tokens

    @Test func todayTokensSumsOnlyTodaysTasks() {
        var board = TaskBoard()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = at(0)   // 1970-01-01 00:16:40 UTC
        _ = board.apply(PreviewFixtures.task("a", created: day, tokens: 1_000), now: day)
        _ = board.apply(PreviewFixtures.task("b", created: day.addingTimeInterval(60), tokens: 500), now: day)
        _ = board.apply(PreviewFixtures.task("old", created: day.addingTimeInterval(-86_400 * 2), tokens: 9_000), now: day)
        #expect(board.todayTokens(now: day.addingTimeInterval(120), calendar: calendar) == 1_500)
    }

    // MARK: peek

    @Test func peekOnEnteringEachAttentionState() {
        var board = TaskBoard()
        let id = UUID()
        _ = board.apply(PreviewFixtures.task("Add dark mode", state: .plan, id: id), now: at(1))
        let ready = board.apply(PreviewFixtures.task("Add dark mode", state: .awaitingApproval, id: id), now: at(2))
        #expect(ready?.kind == .planReady && ready?.text == "Add dark mode: plan ready, approve?" && ready?.taskID == id)
        let done = board.apply(PreviewFixtures.task("Add dark mode", state: .done, id: id), now: at(3))
        #expect(done?.kind == .done && done?.text == "Add dark mode: done")
    }

    @Test func peekFailedAndNeedsInput() {
        var board = TaskBoard()
        let failed = board.apply(PreviewFixtures.task("X", state: .failed, failure: .claudeError("boom")), now: at(1))
        #expect(failed?.kind == .failed && failed?.text == "X: failed")
        let parked = board.apply(PreviewFixtures.task("Y", state: .awaitingInput, wait: .noTestCommand, resume: .test), now: at(1))
        #expect(parked?.kind == .needsInput && parked?.text == "Y: No test command found")
    }

    @Test func noPeekWhenTheStateDidNotChange() {
        var board = TaskBoard()
        let id = UUID()
        #expect(board.apply(PreviewFixtures.task(state: .awaitingApproval, id: id), now: at(1)) != nil)
        #expect(board.apply(PreviewFixtures.task(state: .awaitingApproval, id: id, tokens: 5), now: at(2)) == nil)
    }

    @Test func noPeekForRunningStates() {
        var board = TaskBoard()
        for state in [TaskState.queued, .plan, .code, .test, .fix, .review, .cancelled] {
            #expect(board.apply(PreviewFixtures.task(state: state), now: at(1)) == nil, "\(state)")
        }
    }

    @Test func peekReturnsAfterLeavingAndReenteringTheState() {
        var board = TaskBoard()
        let id = UUID()
        let first = board.apply(PreviewFixtures.task(state: .awaitingInput, id: id, wait: .testTimedOut, resume: .test), now: at(1))
        _ = board.apply(PreviewFixtures.task(state: .test, id: id), now: at(2))
        let second = board.apply(PreviewFixtures.task(state: .awaitingInput, id: id, wait: .testTimedOut, resume: .test), now: at(3))
        #expect(first != nil && second != nil && first != second)   // sequence differs
    }

    @Test func alertsCanBeSwitchedOff() {
        var board = TaskBoard()
        board.showAlerts = false
        #expect(board.apply(PreviewFixtures.task(state: .awaitingApproval), now: at(1)) == nil)
    }
}
