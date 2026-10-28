//
//  WorkflowTask.swift
//  LF-AIWorkflow
//

import Foundation

/// Immutable snapshot of one task. Every change returns a copy.
nonisolated struct WorkflowTask: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let slug: String
    let prompt: String
    let projectRoot: URL
    let documents: [URL]
    let skillDirs: [URL]
    let state: TaskState
    let resumeState: TaskState?
    let waitReason: WaitReason?
    let failure: FailureReason?
    let worktree: Worktree?
    let sessionId: String?
    let planFile: URL?
    let fixAttempts: Int
    let usageByStage: [WorkflowStage: TokenUsage]
    let lastErrors: String?
    let testCommandDisplay: String?
    let reviewFile: URL?
    let createdAt: Date

    var workingDirectory: URL { worktree?.path ?? projectRoot }

    /// Sum of the usage of every stage.
    /// Complexity: O(s) time, O(1) space (s = stages, at most 4)
    var totalUsage: TokenUsage { usageByStage.values.reduce(.zero, +) }

    func with(state: TaskState) -> WorkflowTask { copy(state: state) }
    func with(worktree: Worktree?) -> WorkflowTask { copy(worktree: .some(worktree)) }
    func with(sessionId: String?) -> WorkflowTask { copy(sessionId: .some(sessionId)) }
    func with(failure: FailureReason?) -> WorkflowTask { copy(failure: .some(failure)) }
    func with(fixAttempts: Int) -> WorkflowTask { copy(fixAttempts: fixAttempts) }
    func with(lastErrors: String?) -> WorkflowTask { copy(lastErrors: .some(lastErrors)) }
    func with(planFile: URL?) -> WorkflowTask { copy(planFile: .some(planFile)) }
    func with(reviewFile: URL?) -> WorkflowTask { copy(reviewFile: .some(reviewFile)) }
    func with(testCommandDisplay: String?) -> WorkflowTask { copy(testCommandDisplay: .some(testCommandDisplay)) }
    func with(waiting: WaitReason?, resume: TaskState?) -> WorkflowTask {
        copy(resumeState: .some(resume), waitReason: .some(waiting))
    }

    /// Complexity: O(1) time, O(1) space (dictionary copy is O(s), s <= 4)
    func adding(usage: TokenUsage, for stage: WorkflowStage) -> WorkflowTask {
        var merged = usageByStage
        merged[stage] = (merged[stage] ?? .zero) + usage
        return copy(usageByStage: merged)
    }

    /// Single copy point; a nil parameter keeps the current value, `.some(nil)` clears it.
    private func copy(state: TaskState? = nil, resumeState: TaskState?? = nil, waitReason: WaitReason?? = nil,
                      failure: FailureReason?? = nil, worktree: Worktree?? = nil, sessionId: String?? = nil,
                      planFile: URL?? = nil, fixAttempts: Int? = nil, usageByStage: [WorkflowStage: TokenUsage]? = nil,
                      lastErrors: String?? = nil, testCommandDisplay: String?? = nil, reviewFile: URL?? = nil) -> WorkflowTask {
        WorkflowTask(id: id, title: title, slug: slug, prompt: prompt, projectRoot: projectRoot,
                     documents: documents, skillDirs: skillDirs, state: state ?? self.state,
                     resumeState: resumeState ?? self.resumeState, waitReason: waitReason ?? self.waitReason,
                     failure: failure ?? self.failure, worktree: worktree ?? self.worktree,
                     sessionId: sessionId ?? self.sessionId, planFile: planFile ?? self.planFile,
                     fixAttempts: fixAttempts ?? self.fixAttempts, usageByStage: usageByStage ?? self.usageByStage,
                     lastErrors: lastErrors ?? self.lastErrors, testCommandDisplay: testCommandDisplay ?? self.testCommandDisplay,
                     reviewFile: reviewFile ?? self.reviewFile, createdAt: createdAt)
    }
}
