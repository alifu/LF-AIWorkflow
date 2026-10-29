//
//  WorkflowEngine+Prompts.swift
//  LF-AIWorkflow
//

import Foundation

extension WorkflowStage {
    /// The task state in which this stage runs.
    nonisolated var taskState: TaskState {
        switch self {
        case .plan: .plan
        case .code: .code
        case .fix: .fix
        case .review: .review
        }
    }
}

extension WorkflowEngine {
    private static let checklistCapBytes = 8 * 1024
    private static let graphShareOfPrompt = 3

    /// Gathers the stage's inputs (graph, filtered errors, diff, checklists) and builds the capped prompt.
    /// Returns nil, after failing the task, when the review diff cannot be produced.
    /// Complexity: O(inputs) time, O(inputs) space
    func buildPrompt(for task: WorkflowTask, stage: WorkflowStage) async -> BuiltPrompt? {
        let budget = budgets[task.id] ?? effectiveSettings(for: task.id).budget
        let root = task.workingDirectory
        var graph = GraphContext.empty
        var diff: String?
        var checklists: [String] = []
        let resumes = task.sessionId != nil && effectiveSettings(for: task.id).resumeSessionFor.contains(stage)
        switch stage {
        case .plan: break
        case .code:
            graph = await deps.graph.query(task.title, root: root,
                                           budgetTokens: budget.promptCap(for: .code) / Self.graphShareOfPrompt)
        case .fix:
            let symbols = ContextBuilder.errorSymbols(task.lastErrors ?? "")
            if !symbols.isEmpty {
                graph = await deps.graph.query(symbols.joined(separator: " "), root: root,
                                               budgetTokens: budget.promptCap(for: .fix) / Self.graphShareOfPrompt)
            }
        case .review:
            guard let reviewDiff = await diffForReview(task) else { return nil }
            diff = reviewDiff
            checklists = Self.readChecklists(root: task.projectRoot, rulesMaxTokens: budget.rulesMaxTokens)
        }
        let input = StageContextInput(
            stage: stage, task: task, documents: stage == .plan ? task.documents.map { PlanDocumentReader.read($0, inlineMaxTokens: budget.inlineMaxTokens) } : [],
            sentHashes: resumes ? sentDocumentHashes[task.id] ?? [] : [], graph: graph, diff: diff, errors: task.lastErrors, checklists: checklists,
            findingsForFix: stage == .fix ? findingsForFix[task.id] ?? [] : [])
        let built = ContextBuilder.build(input, budget: budget)
        if stage == .plan { sentDocumentHashes[task.id] = built.sentHashes }
        return built
    }

    private func diffForReview(_ task: WorkflowTask) async -> String? {
        guard let base = task.worktree?.baseCommit ?? task.baseCommit else {
            await fail(task.id, .claudeError("no base revision to diff against")); return nil
        }
        do {
            return try await deps.git.reviewDiff(in: task.workingDirectory, base: base,
                                                markNewFiles: task.worktree != nil)
        } catch {
            if isCurrent(task.id, .review) { await fail(task.id, .claudeError("git diff failed: \(Self.describe(error))")) }
            return nil
        }
    }

    private static func readChecklists(root: URL, rulesMaxTokens: Int) -> [String] {
        ProjectRules.scan(root: root, rulesMaxTokens: rulesMaxTokens).checklists.compactMap { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: checklistCapBytes)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }
}
