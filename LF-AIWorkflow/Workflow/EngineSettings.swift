//
//  EngineSettings.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct EngineSettings: Sendable, Equatable {
    /// Maximum `(fix -> test)` rounds before the task fails.
    let fixLoopCap: Int
    let useWorktree: Bool
    let testCommandOverride: String?
    let budget: TokenBudget
    let policy: StagePolicy
    /// Stages that resume the previous session. Default: only Code resumes the Plan session.
    let resumeSessionFor: Set<WorkflowStage>

    static let `default` = EngineSettings(
        fixLoopCap: 2, useWorktree: true, testCommandOverride: nil, budget: .default,
        policy: .defaults(testCommand: nil), resumeSessionFor: [.code])
}

nonisolated struct TaskDraft: Sendable, Equatable {
    let title: String
    let prompt: String
    let projectRoot: URL
    let documents: [URL]
    let skillDirs: [URL]
}

nonisolated struct EngineDependencies: Sendable {
    let claude: any ClaudeStageRunning
    let tests: any TestRunning
    let graph: any GraphQuerying
    let git: any GitWorking
    let worktrees: any WorktreeProviding
    /// Optional activity sink (the Terminal tab). Nil in tests that do not care.
    var log: (any TaskLogging)? = nil
}

extension EngineSettings {
    /// The engine's settings for one snapshot of the user's Settings. Fix-loop cap, worktree and resume rules keep their defaults.
    /// Complexity: O(s) time, O(s) space (s = stages)
    static func from(_ snapshot: SettingsSnapshot) -> EngineSettings {
        let defaults = EngineSettings.default
        let budget = TokenBudget(
            perTaskMaxTokens: snapshot.taskBudget, inlineMaxTokens: TokenBudget.default.inlineMaxTokens,
            errorMaxTokens: TokenBudget.default.errorMaxTokens, rulesMaxTokens: TokenBudget.default.rulesMaxTokens,
            promptMaxTokens: TokenBudget.default.promptMaxTokens.merging(snapshot.promptCaps) { _, user in user })
        return EngineSettings(
            fixLoopCap: defaults.fixLoopCap, useWorktree: defaults.useWorktree,
            testCommandOverride: defaults.testCommandOverride, budget: budget,
            policy: StagePolicy.defaults(testCommand: nil)
                .overriding(models: snapshot.stageModels, maxTurns: snapshot.stageMaxTurns),
            resumeSessionFor: defaults.resumeSessionFor)
    }
}
