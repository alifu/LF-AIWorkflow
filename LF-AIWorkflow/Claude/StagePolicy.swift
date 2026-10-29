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
    /// Defence in depth, not a sandbox: Claude Code's matcher is prefix-based, so these rules catch the common
    /// forms and variants but cannot stop every way of reaching the same effect.
    static let alwaysDenied = [
        "Bash(git push:*)", "Bash(git merge:*)", "Bash(rm -rf:*)", "Bash(rm -fr:*)", "Bash(rm -r -f:*)",
        "Bash(git -C * push:*)", "Bash(git -c * push:*)", "Bash(git -C * merge:*)", "Bash(git -c * merge:*)",
        "Read(./.env*)", "Read(**/.env*)", "Read(//**/.env*)",
    ]
    /// Read is limited to the stage's working folder; attachments are granted per file by the engine.
    static let scopedRead = "Read(./**)"
    /// `git diff --output=<file>` (and abbreviations like `--out`) writes a file, so Review (read-only) must not reach it.
    /// `:*` only matches "space then anything", so a `*--out*` glob is used to also catch `--output=f` and `--outp f`.
    static let reviewDeniedDiffOutput = ["Bash(git diff *--out*)"]
    /// Code and Fix must not edit Claude config or git metadata/hooks/attributes (`.gitattributes`, `.gitmodules`, `.git/`).
    static let codeDeniedPaths = ["Write(./.claude/**)", "Edit(./.claude/**)", "Write(**/.git*)", "Edit(**/.git*)"]
    static let writeTools = ["Write", "Edit", "NotebookEdit"]

    private let configs: [WorkflowStage: StageConfig]

    private init(configs: [WorkflowStage: StageConfig]) { self.configs = configs }

    /// Complexity: O(1) time, O(1) space
    static func defaults(testCommand: String?) -> StagePolicy {
        var codeTools = [scopedRead, "Write", "Edit", "Grep", "Glob", "Bash(graphify query:*)"]
        if let testCommand, !testCommand.isEmpty { codeTools.append("Bash(\(testCommand))") }
        let readTools = ["Read", "Grep", "Glob"]
        let scopedReadTools = [scopedRead, "Grep", "Glob"]
        return StagePolicy(configs: [
            .plan: StageConfig(model: "opus", escalationModel: nil, permissionMode: .plan,
                               allowedTools: scopedReadTools + ["Bash(graphify query:*)"], disallowedTools: [], maxTurns: 8),
            .code: StageConfig(model: "sonnet", escalationModel: nil, permissionMode: .acceptEdits,
                               allowedTools: codeTools, disallowedTools: [], maxTurns: 20),
            .fix: StageConfig(model: "haiku", escalationModel: "sonnet", permissionMode: .acceptEdits,
                              allowedTools: codeTools, disallowedTools: [], maxTurns: 10),
            .review: StageConfig(model: "opus", escalationModel: nil, permissionMode: .default,
                                 allowedTools: scopedReadTools + ["Bash(git diff:*)"], disallowedTools: [], maxTurns: 8,
                                 builtinTools: readTools + ["Bash"]),
        ])
    }

    /// Effective config: always-denied tools are appended to the stage's list (deduplicated, order kept);
    /// Review additionally can never allow write tools.
    /// Complexity: O(n) time, O(n) space
    func config(for stage: WorkflowStage) -> StageConfig {
        let base = configs[stage]!
        var allowed = base.allowedTools
        var denied = base.disallowedTools + Self.alwaysDenied
        if stage == .code || stage == .fix { denied += Self.codeDeniedPaths }
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
