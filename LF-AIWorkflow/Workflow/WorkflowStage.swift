//
//  WorkflowStage.swift
//  LF-AIWorkflow
//

/// Pipeline stages a Claude run can belong to. Phase 4/7 extend this.
nonisolated enum WorkflowStage: String, Sendable, CaseIterable, Codable {
    case plan, code, fix, review
}
