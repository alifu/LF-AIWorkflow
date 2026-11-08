//
//  TaskRestore.swift
//  LF-AIWorkflow
//

import Foundation

/// Rules for tasks reloaded from disk (TD-028).
nonisolated enum TaskRestore {
    static let interruptedText = "Interrupted: the app was closed while this stage was running"
    static let notStartedText = "Interrupted before it started"

    /// No driver survives a relaunch, so a task persisted mid-stage is parked `awaitingInput` with its
    /// stage as `resumeState`; a task still `queued` (no worktree decision recorded) is failed.
    /// Waiting and terminal tasks are returned as they were.
    /// Complexity: O(n) time, O(n) space
    static func interrupted(_ tasks: [WorkflowTask], now: Date) -> [WorkflowTask] {
        tasks.map { task in
            switch task.state {
            case .plan, .code, .test, .fix, .review:
                task.with(state: .awaitingInput).with(waiting: .other(interruptedText), resume: task.state)
            case .queued:
                task.with(state: .failed).with(failure: .worktree(notStartedText)).with(finishedAt: now)
            case .awaitingApproval, .awaitingInput, .done, .failed, .cancelled:
                task
            }
        }
    }
}
