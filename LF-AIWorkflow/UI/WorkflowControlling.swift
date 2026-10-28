//
//  WorkflowControlling.swift
//  LF-AIWorkflow
//

import Foundation

/// What the views need from the view model; lets previews run without an engine.
@MainActor
protocol WorkflowControlling: TaskDeciding {
    var rows: [TaskRowModel] { get }
    var summary: CollapsedSummary { get }
    var todayTokens: Int { get }
    var peek: PeekMessage? { get }
    var lastError: String? { get }
    var logRevision: Int { get }

    func submit(_ draft: TaskDraft) async
    func resume(_ id: UUID, raising tokens: Int) async
    func skipTests(_ id: UUID) async
    func clearDone()
    func clearError()
    func openWorktree(_ id: UUID)
    func log(for id: UUID) async -> [TaskLogLine]
    /// Latest snapshot of a task (plan and review paths, working directory); nil once it is gone.
    func task(_ id: UUID) -> WorkflowTask?
}

extension WorkflowViewModel: WorkflowControlling {}
