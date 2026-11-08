//
//  TaskTransitionTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct TaskTransitionTests {
    private static let legal: Set<[TaskState]> = {
        var edges: Set<[TaskState]> = [
            [.queued, .plan], [.queued, .code], [.done, .fix], [.plan, .awaitingApproval], [.awaitingApproval, .code], [.code, .test],
            [.test, .review], [.test, .fix], [.fix, .test], [.review, .done],
        ]
        let nonTerminal: [TaskState] = [.queued, .plan, .awaitingApproval, .code, .test, .fix, .review, .awaitingInput]
        for s in nonTerminal {
            edges.insert([s, .failed]); edges.insert([s, .cancelled])
            if s != .awaitingInput { edges.insert([s, .awaitingInput]) }
        }
        return edges
    }()

    /// A task in `state`; awaitingInput resumes to `.code`.
    private func task(in state: TaskState, attempts: Int = 0) -> WorkflowTask {
        WorkflowModelTests.makeTask().with(state: state).with(fixAttempts: attempts)
            .with(waiting: nil, resume: state == .awaitingInput ? .code : nil)
    }

    @Test func tableMatchesLegalEdgesForTaskWithoutResume() {
        for from in TaskState.allCases where from != .awaitingInput && from != .failed {
            for to in TaskState.allCases {
                let ok = (try? TaskTransitions.move(task(in: from), to: to, fixLoopCap: 3)) != nil
                #expect(ok == Self.legal.contains([from, to]), "\(from) -> \(to)")
            }
        }
    }

    @Test func awaitingInputOnlyReturnsToResumeState() {
        for to in TaskState.allCases {
            let ok = (try? TaskTransitions.move(task(in: .awaitingInput), to: to, fixLoopCap: 3)) != nil
            #expect(ok == [.code, .failed, .cancelled].contains(to), "awaitingInput -> \(to)")
        }
    }

    @Test func canMoveAgreesWithTableForNonResumeStates() {
        for from in TaskState.allCases where from != .awaitingInput {
            for to in TaskState.allCases {
                let retry = from == .failed && TaskTransitions.retryTargets.contains(to)
                #expect(TaskTransitions.canMove(from: from, to: to) == (Self.legal.contains([from, to]) || retry))
            }
        }
        #expect(TaskTransitions.table[.done] == [.fix])
    }

    @Test func illegalTransitionError() {
        #expect(throws: WorkflowError.illegalTransition(from: .plan, to: .code)) {
            _ = try TaskTransitions.move(task(in: .plan), to: .code, fixLoopCap: 3)
        }
        #expect(throws: WorkflowError.illegalTransition(from: .review, to: .fix)) {
            _ = try TaskTransitions.move(task(in: .review), to: .fix, fixLoopCap: 3)
        }
        #expect(throws: WorkflowError.illegalTransition(from: .done, to: .plan)) {
            _ = try TaskTransitions.move(task(in: .done), to: .plan, fixLoopCap: 3)
        }
        #expect(throws: WorkflowError.illegalTransition(from: .cancelled, to: .cancelled)) {
            _ = try TaskTransitions.move(task(in: .cancelled), to: .cancelled, fixLoopCap: 3)
        }
    }

    @Test func fixIncrementsAttemptsAndHonoursCap() throws {
        var t = task(in: .test)
        for expected in 1...2 {
            t = try TaskTransitions.move(t, to: .fix, fixLoopCap: 2)
            #expect(t.fixAttempts == expected)
            t = try TaskTransitions.move(t, to: .test, fixLoopCap: 2)
        }
        #expect(throws: WorkflowError.fixLoopCapReached) {
            _ = try TaskTransitions.move(t, to: .fix, fixLoopCap: 2)
        }
    }

    @Test func awaitingInputRecordsResumeState() throws {
        let t = try TaskTransitions.move(task(in: .test), to: .awaitingInput, fixLoopCap: 3)
        #expect(t.state == .awaitingInput)
        #expect(t.resumeState == .test)
    }

    @Test func resumingClearsWaitMetadataAndReturnsToResumeState() throws {
        let waiting = task(in: .code).with(waiting: .noTestCommand, resume: nil)
        let parked = try TaskTransitions.move(waiting, to: .awaitingInput, fixLoopCap: 3)
        let resumed = try TaskTransitions.move(parked, to: .code, fixLoopCap: 3)
        #expect(resumed.state == .code)
        #expect(resumed.resumeState == nil)
        #expect(resumed.waitReason == nil)
    }

    @Test func skipTestsMovesTestResumeToReview() throws {
        let parked = try TaskTransitions.move(task(in: .test), to: .awaitingInput, fixLoopCap: 3)
        #expect(try TaskTransitions.move(parked, to: .review, fixLoopCap: 3).state == .review)
        #expect(try TaskTransitions.move(parked, to: .test, fixLoopCap: 3).state == .test)
        #expect(throws: WorkflowError.illegalTransition(from: .awaitingInput, to: .code)) {
            _ = try TaskTransitions.move(parked, to: .code, fixLoopCap: 3)
        }
    }

    @Test func resumingIntoFixDoesNotCountAnotherAttempt() throws {
        let fixing = try TaskTransitions.move(task(in: .test), to: .fix, fixLoopCap: 2)
        let parked = try TaskTransitions.move(fixing, to: .awaitingInput, fixLoopCap: 2)
        let resumed = try TaskTransitions.move(parked, to: .fix, fixLoopCap: 2)
        #expect(resumed.fixAttempts == 1)
    }

    @Test func moveReturnsCopy() throws {
        let original = task(in: .queued)
        let moved = try TaskTransitions.move(original, to: .plan, fixLoopCap: 3)
        #expect(original.state == .queued)
        #expect(moved.state == .plan)
    }

    // MARK: - Retry (TD-043)

    private func failed(at stage: TaskState?, attempts: Int = 0, reason: FailureReason? = .claudeError("x")) -> WorkflowTask {
        task(in: .failed).with(failure: reason).with(retryState: stage).with(fixAttempts: attempts)
            .with(finishedAt: Date(timeIntervalSince1970: 5))
    }

    @Test func failedTaskRetriesOnlyIntoTheStageItFailedIn() throws {
        for stage in [TaskState.queued, .plan, .code, .test, .fix, .review] {
            for to in TaskState.allCases {
                let ok = (try? TaskTransitions.move(failed(at: stage), to: to, fixLoopCap: 3)) != nil
                #expect(ok == (to == stage), "failed(\(stage)) -> \(to)")
            }
        }
    }

    @Test func retryClearsFailureAndFinishedAt() throws {
        let moved = try TaskTransitions.move(failed(at: .code), to: .code, fixLoopCap: 3)
        #expect(moved.state == .code)
        #expect(moved.failure == nil)
        #expect(moved.retryState == nil)
        #expect(moved.finishedAt == nil)
    }

    @Test func retryWithoutRecordedStageGoesBackToQueuedAndNeedsAFailure() throws {
        #expect(try TaskTransitions.move(failed(at: nil), to: .queued, fixLoopCap: 3).state == .queued)
        #expect(throws: WorkflowError.self) {
            _ = try TaskTransitions.move(failed(at: .code, reason: nil), to: .code, fixLoopCap: 3)
        }
    }

    @Test func retryAfterFixLoopExhaustionResetsAttempts() throws {
        let moved = try TaskTransitions.move(failed(at: .test, attempts: 2, reason: .fixLoopExhausted(attempts: 2)),
                                             to: .test, fixLoopCap: 2)
        #expect(moved.fixAttempts == 0)
        let other = try TaskTransitions.move(failed(at: .test, attempts: 1), to: .test, fixLoopCap: 2)
        #expect(other.fixAttempts == 1)
    }
}
