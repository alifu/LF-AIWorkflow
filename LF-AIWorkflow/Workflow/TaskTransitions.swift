//
//  TaskTransitions.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum WorkflowError: Error, Sendable, Equatable {
    case illegalTransition(from: TaskState, to: TaskState)
    case unknownTask(UUID)
    case fixLoopCapReached
    case invalidTestTarget(String)
    /// `sendToFix` was called without findings.
    case noFindings
    /// The task is still moving or waiting on the user; stop or finish it first.
    case taskActive(UUID)
    case noWorktree(UUID)
    case worktreeRemovalFailed(String)
    /// The task's worktree directory no longer exists (TD-122).
    case worktreeMissing(String)
}

/// The legal edges of the task state machine (plan §6) and the guarded `move`.
nonisolated enum TaskTransitions {
    /// States a parked task may be resumed into (the guard narrows this to the task's own `resumeState`).
    private static let resumable: Set<TaskState> = [.plan, .code, .test, .fix, .review]
    private static let abortable: Set<TaskState> = [.failed, .cancelled]

    /// States a failed task can be retried into (the guard narrows this to the stage it failed in).
    static let retryTargets: Set<TaskState> = [.queued, .plan, .code, .test, .fix, .review]

    /// `targets` plus the abort edges every non-terminal state has.
    private static func edges(_ targets: TaskState...) -> Set<TaskState> {
        Set(targets).union(abortable)
    }

    static let table: [TaskState: Set<TaskState>] = [
        .queued: edges(.plan, .code, .awaitingInput),
        .plan: edges(.awaitingApproval, .awaitingInput),
        .awaitingApproval: edges(.code, .awaitingInput),
        .code: edges(.test, .awaitingInput),
        .test: edges(.review, .fix, .awaitingInput),
        .fix: edges(.test, .awaitingInput),
        .review: edges(.done, .awaitingInput),
        .awaitingInput: resumable.union(abortable),
        .failed: retryTargets,
        .done: [.fix], .cancelled: [],
    ]

    /// Complexity: O(1) time, O(1) space
    static func canMove(from: TaskState, to: TaskState) -> Bool {
        table[from]?.contains(to) ?? false
    }

    /// Applies the table plus guards: `test -> fix` needs `fixAttempts < fixLoopCap` and counts one attempt;
    /// `failed` may only return to the stage it failed in (`retry`, needs a recorded failure);
    /// `awaitingInput` may only return to `resumeState` (or `review` when that is `test`, "skip tests").
    /// Parking records `resumeState`; resuming clears the wait metadata. Entering a terminal state stamps
    /// `finishedAt` with `now` (once). The input task is untouched.
    /// Complexity: O(1) time, O(1) space
    static func move(_ task: WorkflowTask, to: TaskState, fixLoopCap: Int,
                     now: Date = Date()) throws(WorkflowError) -> WorkflowTask {
        let from = task.state
        guard canMove(from: from, to: to), isAllowedResume(task, to: to) else {
            throw .illegalTransition(from: from, to: to)
        }
        switch (from, to) {
        case (.done, .fix):
            // "Send findings to Fix" (TD-045): a finished task goes back into the fix loop with a fresh attempt count.
            return task.with(state: .fix).with(fixAttempts: 0).with(finishedAt: nil)
        case (.test, .fix):
            guard task.fixAttempts < fixLoopCap else { throw .fixLoopCapReached }
            return task.with(state: .fix).with(fixAttempts: task.fixAttempts + 1)
        case (_, .awaitingInput):
            return task.with(state: .awaitingInput).with(waiting: task.waitReason, resume: from)
        case (.failed, _):
            let fresh = task.with(state: to).with(failure: nil).with(retryState: nil).with(finishedAt: nil)
            if case .fixLoopExhausted = task.failure { return fresh.with(fixAttempts: 0) }
            return fresh
        case (.awaitingInput, _) where !to.isTerminal:
            return task.with(state: to).with(waiting: nil, resume: nil)
        default:
            let moved = task.with(state: to)
            return to.isTerminal && moved.finishedAt == nil ? moved.with(finishedAt: now) : moved
        }
    }

    private static func isAllowedResume(_ task: WorkflowTask, to: TaskState) -> Bool {
        if task.state == .failed { return task.failure != nil && to == (task.retryState ?? .queued) }
        guard task.state == .awaitingInput, !abortable.contains(to) else { return true }
        guard let resume = task.resumeState else { return false }
        return to == resume || (resume == .test && to == .review)
    }
}
