//
//  TaskState.swift
//  LF-AIWorkflow
//

import Foundation

/// Lifecycle state of a workflow task (plan §6).
nonisolated enum TaskState: String, Sendable, Hashable, CaseIterable, Codable {
    case queued, plan, awaitingApproval, code, test, fix, review, done, failed, cancelled, awaitingInput

    /// The Claude stage this state runs, if any.
    var claudeStage: WorkflowStage? {
        switch self {
        case .plan: .plan
        case .code: .code
        case .fix: .fix
        case .review: .review
        case .queued, .awaitingApproval, .test, .done, .failed, .cancelled, .awaitingInput: nil
        }
    }

    /// Terminal states end the task; only `failed` can be retried.
    var isTerminal: Bool {
        switch self {
        case .done, .failed, .cancelled: true
        default: false
        }
    }
}

nonisolated enum WaitReason: Sendable, Equatable, Codable {
    case budgetExceeded(spent: Int, limit: Int), dayBudgetExceeded(spent: Int, limit: Int), noTestCommand, testTimedOut, testEntryModified(String), toolMissing(Tool), other(String)

    var allowsSkippingTests: Bool {
        switch self {
        case .noTestCommand, .testTimedOut, .testEntryModified: true
        default: false
        }
    }
}

nonisolated enum FailureReason: Sendable, Equatable, Codable {
    case claudeError(String), fixLoopExhausted(attempts: Int), worktree(String), spawn(String), invalidCommand(String)
}

nonisolated struct Worktree: Sendable, Equatable, Codable {
    let path: URL
    let branch: String
    let baseCommit: String
}
