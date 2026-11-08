//
//  WorkflowStage.swift
//  LF-AIWorkflow
//

/// Pipeline stages a Claude run can belong to. Phase 4/7 extend this.
nonisolated enum WorkflowStage: String, Sendable, CaseIterable, Codable {
    case plan, code, fix, review
}

extension WorkflowStage {
    /// Human-readable stage name for the UI.
    nonisolated var displayName: String {
        switch self {
        case .plan: "Plan"
        case .code: "Code"
        case .fix: "Fix"
        case .review: "Review"
        }
    }
}
