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
    /// Tokens allowed per calendar day across all tasks; 0 means no daily limit.
    var dayBudget: Int = 0

    static let `default` = EngineSettings(
        fixLoopCap: 2, useWorktree: false, testCommandOverride: nil, budget: .default,
        policy: .defaults(testCommand: nil), resumeSessionFor: [.code])
}

nonisolated struct TaskDraft: Sendable, Equatable {
    let title: String
    let prompt: String
    let projectRoot: URL
    let documents: [URL]
    let skillDirs: [URL]
    /// Skip Plan and approval and begin at Code (TD-044).
    var startAtCode: Bool = false
    /// Per-task worktree choice; nil follows `EngineSettings.useWorktree`.
    var useWorktree: Bool? = nil
}

nonisolated struct EngineDependencies: Sendable {
    let claude: any ClaudeStageRunning
    let tests: any TestRunning
    let graph: any GraphQuerying
    let git: any GitWorking
    let worktrees: any WorktreeProviding
    /// Optional activity sink (the Terminal tab). Nil in tests that do not care.
    var log: (any TaskLogging)? = nil
    /// Longest a Code/Fix stage waits for `graphify update` before moving on.
    var graphWait: Duration = .seconds(60)
    /// Daily token ledger; nil disables the daily cap.
    var ledger: DayTokenLedger? = nil
    /// Task persistence (`ProjectStore`); nil keeps tasks in memory only.
    var store: (any TaskPersisting)? = nil
}

nonisolated extension EngineSettings {
    /// Same settings with the worktree choice replaced. Complexity: O(1) time, O(1) space
    func with(useWorktree: Bool) -> EngineSettings {
        EngineSettings(fixLoopCap: fixLoopCap, useWorktree: useWorktree, testCommandOverride: testCommandOverride,
                       budget: budget, policy: policy, resumeSessionFor: resumeSessionFor, dayBudget: dayBudget)
    }

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
            resumeSessionFor: defaults.resumeSessionFor, dayBudget: snapshot.dayBudget)
    }
}
