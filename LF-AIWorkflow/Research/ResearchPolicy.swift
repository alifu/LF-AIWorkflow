//
//  ResearchPolicy.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum ResearchStage: String, Sendable, CaseIterable, Codable {
    case extract, analyze, followUp
}

nonisolated struct ResearchRunRequest: Sendable, Equatable {
    let stage: ResearchStage
    let config: StageConfig
    let prompt: String
    let sessionId: String?
    let workingDirectory: URL
}

nonisolated protocol ResearchClaudeRunning: Sendable {
    func run(_ request: ResearchRunRequest) -> AsyncThrowingStream<StageRunEvent, Error>
}

/// Research stage table. Tools are never overridable; only models are.
nonisolated struct ResearchPolicy: Sendable, Equatable {
    static let deniedTools = ["Bash", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch", "Task", "Agent"]

    private let models: [ResearchStage: String]

    private init(models: [ResearchStage: String]) { self.models = models }

    /// Complexity: O(1) time, O(1) space
    static func defaults() -> ResearchPolicy {
        ResearchPolicy(models: [.extract: "haiku", .analyze: "sonnet", .followUp: "sonnet"])
    }

    /// Complexity: O(n) time, O(n) space (n = denied tools)
    func config(for stage: ResearchStage, deep: Bool, systemPrompt: String) -> StageConfig {
        var seen = Set<String>()
        let denied = (Self.deniedTools + StagePolicy.alwaysDenied).filter { seen.insert($0).inserted }
        let defaultModel = models[stage] ?? "sonnet"
        let model = (deep && stage != .extract) ? "opus" : defaultModel
        let isExtract = stage == .extract
        return StageConfig(
            model: model, escalationModel: nil, permissionMode: .default,
            allowedTools: isExtract ? [] : ["Read(./**)"], disallowedTools: denied,
            maxTurns: isExtract ? 1 : (stage == .analyze ? 6 : 4),
            builtinTools: isExtract ? [] : ["Read"], isolated: true, appendSystemPrompt: systemPrompt)
    }

    /// New policy with model overrides; tools stay fixed.
    /// Complexity: O(s) time, O(s) space
    func overriding(models overrides: [ResearchStage: String]) -> ResearchPolicy {
        ResearchPolicy(models: models.merging(overrides) { _, new in new })
    }
}
