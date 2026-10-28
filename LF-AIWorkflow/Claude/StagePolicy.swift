//
//  StagePolicy.swift
//  LF-AIWorkflow
//

nonisolated enum PermissionMode: String, Sendable, Codable {
    case plan, acceptEdits, `default`
}

/// Per-stage CLI settings. `ClaudeCommandBuilder` turns this into flags.
nonisolated struct StageConfig: Sendable, Equatable, Codable {
    let model: String
    /// Fix stage: model to switch to after repeated failure (used by Phase 4).
    let escalationModel: String?
    let permissionMode: PermissionMode
    let allowedTools: [String]
    let disallowedTools: [String]
    let maxTurns: Int
    /// Built-in tool set (`--tools`): nil = CLI default, `[]` = none.
    let builtinTools: [String]?
    /// Adds `--strict-mcp-config --setting-sources project --disable-slash-commands`.
    let isolated: Bool
    let appendSystemPrompt: String?

    init(model: String, escalationModel: String?, permissionMode: PermissionMode, allowedTools: [String],
         disallowedTools: [String], maxTurns: Int, builtinTools: [String]? = nil, isolated: Bool = false,
         appendSystemPrompt: String? = nil) {
        self.model = model
        self.escalationModel = escalationModel
        self.permissionMode = permissionMode
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.maxTurns = maxTurns
        self.builtinTools = builtinTools
        self.isolated = isolated
        self.appendSystemPrompt = appendSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(model: try c.decode(String.self, forKey: .model),
                  escalationModel: try c.decodeIfPresent(String.self, forKey: .escalationModel),
                  permissionMode: try c.decode(PermissionMode.self, forKey: .permissionMode),
                  allowedTools: try c.decode([String].self, forKey: .allowedTools),
                  disallowedTools: try c.decode([String].self, forKey: .disallowedTools),
                  maxTurns: try c.decode(Int.self, forKey: .maxTurns),
                  builtinTools: try c.decodeIfPresent([String].self, forKey: .builtinTools),
                  isolated: try c.decodeIfPresent(Bool.self, forKey: .isolated) ?? false,
                  appendSystemPrompt: try c.decodeIfPresent(String.self, forKey: .appendSystemPrompt))
    }
}

/// Pure table of stage permissions and models (plan §3 "Stage policy").
nonisolated struct StagePolicy: Sendable, Equatable {
    static let alwaysDenied = ["Bash(git push:*)", "Bash(git merge:*)", "Bash(rm -rf:*)", "Read(./.env*)"]
    /// `git diff --output=<file>` (and abbreviations like `--out`) writes a file, so Review (read-only) must not reach it.
    /// `:*` only matches "space then anything", so a `*--out*` glob is used to also catch `--output=f` and `--outp f`.
    static let reviewDeniedDiffOutput = ["Bash(git diff *--out*)"]
    static let writeTools = ["Write", "Edit", "NotebookEdit"]

    private let configs: [WorkflowStage: StageConfig]

    private init(configs: [WorkflowStage: StageConfig]) { self.configs = configs }

    /// Complexity: O(1) time, O(1) space
    static func defaults(testCommand: String?) -> StagePolicy {
        var codeTools = ["Read", "Write", "Edit", "Grep", "Glob", "Bash(graphify:*)"]
        if let testCommand, !testCommand.isEmpty { codeTools.append("Bash(\(testCommand))") }
        let readTools = ["Read", "Grep", "Glob"]
        return StagePolicy(configs: [
            .plan: StageConfig(model: "opus", escalationModel: nil, permissionMode: .plan,
                               allowedTools: readTools + ["Bash(graphify:*)"], disallowedTools: [], maxTurns: 8),
            .code: StageConfig(model: "sonnet", escalationModel: nil, permissionMode: .acceptEdits,
                               allowedTools: codeTools, disallowedTools: [], maxTurns: 20),
            .fix: StageConfig(model: "haiku", escalationModel: "sonnet", permissionMode: .acceptEdits,
                              allowedTools: codeTools, disallowedTools: [], maxTurns: 10),
            .review: StageConfig(model: "opus", escalationModel: nil, permissionMode: .default,
                                 allowedTools: readTools + ["Bash(git diff:*)"], disallowedTools: [], maxTurns: 8),
        ])
    }

    /// Effective config: always-denied tools are appended to the stage's list (deduplicated, order kept);
    /// Review additionally can never allow write tools.
    /// Complexity: O(n) time, O(n) space
    func config(for stage: WorkflowStage) -> StageConfig {
        let base = configs[stage]!
        var allowed = base.allowedTools
        var denied = base.disallowedTools + Self.alwaysDenied
        if stage == .review {
            allowed.removeAll { Self.writeTools.contains($0) }
            denied += Self.writeTools + Self.reviewDeniedDiffOutput
        }
        var seen = Set<String>()
        denied = denied.filter { seen.insert($0).inserted }
        return StageConfig(model: base.model, escalationModel: base.escalationModel,
                           permissionMode: base.permissionMode, allowedTools: allowed,
                           disallowedTools: denied, maxTurns: base.maxTurns,
                           builtinTools: base.builtinTools, isolated: base.isolated,
                           appendSystemPrompt: base.appendSystemPrompt)
    }

    /// New policy with the user's model and turn overrides applied per stage; missing entries keep the table value.
    /// Complexity: O(s) time, O(s) space (s = stages)
    func overriding(models: [WorkflowStage: String], maxTurns: [WorkflowStage: Int]) -> StagePolicy {
        var copy = configs
        for (stage, base) in configs {
            copy[stage] = StageConfig(
                model: models[stage] ?? base.model, escalationModel: base.escalationModel,
                permissionMode: base.permissionMode, allowedTools: base.allowedTools,
                disallowedTools: base.disallowedTools, maxTurns: maxTurns[stage] ?? base.maxTurns,
                builtinTools: base.builtinTools, isolated: base.isolated, appendSystemPrompt: base.appendSystemPrompt)
        }
        return StagePolicy(configs: copy)
    }

    /// New policy with one stage replaced; the receiver is unchanged.
    func replacing(_ stage: WorkflowStage, with config: StageConfig) -> StagePolicy {
        var copy = configs
        copy[stage] = config
        return StagePolicy(configs: copy)
    }
}
