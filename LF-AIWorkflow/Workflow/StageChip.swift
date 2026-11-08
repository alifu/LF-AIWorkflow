//
//  StageChip.swift
//  LF-AIWorkflow
//

import Foundation

/// Steps shown in the stage strip. Test is not a Claude stage, so this is wider than `WorkflowStage`.
nonisolated enum PipelineStep: String, Sendable, CaseIterable {
    case plan, code, test, fix, review

    /// The step a running state belongs to; nil for waiting and terminal states.
    init?(state: TaskState) {
        switch state {
        case .plan: self = .plan
        case .code: self = .code
        case .test: self = .test
        case .fix: self = .fix
        case .review: self = .review
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .plan: "Plan"
        case .code: "Code"
        case .test: "Test"
        case .fix: "Fix"
        case .review: "Review"
        }
    }
}

nonisolated struct StageChip: Sendable, Equatable, Identifiable {
    enum Status: Sendable, Equatable {
        case pending, active, done, failed

        var spoken: String {
            switch self {
            case .pending: "pending"
            case .active: "active"
            case .done: "done"
            case .failed: "failed"
            }
        }
    }

    let step: PipelineStep
    let status: Status
    /// Counter such as "1/2" (fix attempts).
    let detail: String?

    var id: PipelineStep { step }

    /// "Plan, done" / "Fix, active, 1 of 2".
    var accessibilityLabel: String {
        var label = "\(step.displayName), \(status.spoken)"
        if let detail { label += ", " + detail.replacingOccurrences(of: "/", with: " of ") }
        return label
    }

    // MARK: - Derivation

    /// Where the pipeline cursor sits: steps before it are done, steps after it pending.
    private struct Cursor { let index: Int; let status: Status }

    /// Chips for the stage strip. The Fix chip shows the attempt counter and is dropped once the task passed
    /// the Test step without needing any fix.
    /// Complexity: O(1) time, O(1) space (five fixed chips)
    static func chips(for task: WorkflowTask, fixLoopCap: Int) -> [StageChip] {
        let steps = PipelineStep.allCases
        let cursor = cursor(for: task)
        let counter = task.fixAttempts > 0 ? "\(task.fixAttempts)/\(fixLoopCap)" : nil
        var result: [StageChip] = []
        for (index, step) in steps.enumerated() {
            var status: Status = index < cursor.index ? .done : (index == cursor.index ? cursor.status : .pending)
            var detail: String?
            switch step {
            case .test where task.state == .fix:
                status = .failed
            case .test where task.state == .failed && task.failure.isFixLoopExhausted:
                status = .failed
            case .fix where task.state == .fix:
                status = .active; detail = counter
            case .fix where task.fixAttempts > 0:
                if status != .failed { status = .done }
                detail = counter
            case .fix where cursor.index >= PipelineStep.review.index && task.fixAttempts == 0:
                continue
            default:
                break
            }
            result.append(StageChip(step: step, status: status, detail: detail))
        }
        return result
    }

    private static func cursor(for task: WorkflowTask) -> Cursor {
        switch task.state {
        case .queued: Cursor(index: 0, status: .pending)
        case .plan: Cursor(index: 0, status: .active)
        case .awaitingApproval: Cursor(index: 1, status: .pending)
        case .code: Cursor(index: 1, status: .active)
        case .test: Cursor(index: 2, status: .active)
        case .fix: Cursor(index: 3, status: .active)
        case .review: Cursor(index: 4, status: .active)
        case .done: Cursor(index: PipelineStep.allCases.count, status: .done)
        case .awaitingInput: Cursor(index: (task.resumeState.flatMap(PipelineStep.init(state:)) ?? reached(task)).index, status: .active)
        case .failed:
            task.failure.isFixLoopExhausted
                ? Cursor(index: PipelineStep.review.index, status: .pending)
                : Cursor(index: reached(task).index, status: .failed)
        case .cancelled: Cursor(index: reached(task).index, status: .pending)
        }
    }

    /// Best guess of the step a failed, cancelled or parked task got to, from the data it carries.
    private static func reached(_ task: WorkflowTask) -> PipelineStep {
        if task.usageByStage[.review] != nil || task.reviewFile != nil { return .review }
        if task.fixAttempts > 0 { return .fix }
        if task.usageByStage[.code] != nil || task.worktree != nil { return .code }
        return .plan
    }
}

extension PipelineStep {
    nonisolated var index: Int { PipelineStep.allCases.firstIndex(of: self) ?? 0 }
}

nonisolated private extension Optional where Wrapped == FailureReason {
    var isFixLoopExhausted: Bool {
        if case .fixLoopExhausted? = self { return true }
        return false
    }
}
