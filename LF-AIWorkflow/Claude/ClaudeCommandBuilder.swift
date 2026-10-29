//
//  ClaudeCommandBuilder.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum ClaudeCommandError: Error, Sendable, Equatable {
    case invalidModel(String)
    case invalidMaxTurns(Int)
    case invalidSessionId(String)
    case invalidToolRule(String)
    case relativeDirectory(String)
    case invalidToolName(String)
    case invalidSystemPrompt
}

/// Turns a `StageConfig` into `claude` CLI arguments, validating every value at the boundary.
nonisolated enum ClaudeCommandBuilder {
    static let maxTurnsRange = 1...100
    static let maxSystemPromptBytes = 8 * 1024
    private static let modelCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._[]-")
    /// Exact variable names removed from the child environment (session identity only; auth/provider vars such as
    /// `CLAUDE_CODE_OAUTH_TOKEN` or `CLAUDE_CODE_USE_BEDROCK` must survive). Shared by builder and `ClaudeSession`.
    /// - `CLAUDECODE`: marks "running inside Claude Code"; makes a nested `claude -p` behave as a sub-session.
    /// - `CLAUDE_CODE_ENTRYPOINT`: records how the parent was launched; would mislabel this run.
    /// - `CLAUDE_CODE_SSE_PORT`: the parent IDE integration port; would attach the child to the parent's IDE.
    static let droppedEnvironmentKeys: Set<String> = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"]

    /// Fixed order: `-p --output-format stream-json --verbose --model --max-turns --permission-mode
    /// [--allowedTools] [--disallowedTools] [--add-dir]… [--resume]`. Tool lists are one comma-joined argument, so rules may not contain commas.
    /// Complexity: O(n) time, O(n) space
    static func arguments(config: StageConfig, sessionId: String?, addDirs: [URL]) throws(ClaudeCommandError) -> [String] {
        guard isValidModel(config.model) else { throw .invalidModel(config.model) }
        guard maxTurnsRange.contains(config.maxTurns) else { throw .invalidMaxTurns(config.maxTurns) }
        if let sessionId, !isValidSessionId(sessionId) { throw .invalidSessionId(sessionId) }
        for rule in config.allowedTools + config.disallowedTools where rule.isEmpty || rule.contains(",") || rule.hasPrefix("-") {
            throw .invalidToolRule(rule)
        }
        for name in config.builtinTools ?? [] where !isValidToolName(name) { throw .invalidToolName(name) }
        // A leading `-` would be read by the CLI as a flag, so the prompt is rejected rather than passed through.
        if let prompt = config.appendSystemPrompt,
           prompt.hasPrefix("-") || prompt.utf8.count > maxSystemPromptBytes || prompt.utf8.contains(0) {
            throw .invalidSystemPrompt
        }
        var dirPaths: [String] = []
        for dir in addDirs {
            guard dir.path.hasPrefix("/") else { throw .relativeDirectory(dir.path) }
            dirPaths.append(dir.standardizedFileURL.path)
        }

        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--model", config.model,
                    "--max-turns", String(config.maxTurns),
                    "--permission-mode", config.permissionMode.rawValue]
        if let tools = config.builtinTools { args += ["--tools", tools.joined(separator: ",")] }
        // Never load project/local settings (hooks, apiKeyHelper, MCP, allow rules) from a repo the stages edit.
        args += config.isolated ? ["--strict-mcp-config", "--setting-sources", "project", "--disable-slash-commands"]
                                : ["--strict-mcp-config", "--setting-sources", "user"]
        if let prompt = config.appendSystemPrompt { args += ["--append-system-prompt", prompt] }
        if !config.allowedTools.isEmpty { args += ["--allowedTools", config.allowedTools.joined(separator: ",")] }
        if !config.disallowedTools.isEmpty { args += ["--disallowedTools", config.disallowedTools.joined(separator: ",")] }
        for path in dirPaths { args += ["--add-dir", path] }
        if let sessionId { args += ["--resume", sessionId] }
        return args
    }

    /// Complexity: O(n) time, O(n) space
    static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in !droppedEnvironmentKeys.contains(key) }
    }

    /// Complexity: O(n) time, O(n) space
    static func environment(base: [String: String], searchPath: [String]) -> [String: String] {
        var env = sanitized(base)
        env["PATH"] = searchPath.joined(separator: ":")
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        return env
    }

    /// Complexity: O(n) time, O(n) space
    static func invocation(executable: URL, config: StageConfig, sessionId: String?, addDirs: [URL],
                           workingDirectory: URL, prompt: String, baseEnvironment: [String: String],
                           searchPath: [String]) throws(ClaudeCommandError) -> ProcessInvocation {
        ProcessInvocation(
            executable: executable,
            arguments: try arguments(config: config, sessionId: sessionId, addDirs: addDirs),
            environment: environment(base: baseEnvironment, searchPath: searchPath),
            workingDirectory: workingDirectory,
            stdin: Data(prompt.utf8))
    }

    private static func isValidModel(_ model: String) -> Bool {
        !model.isEmpty && !model.hasPrefix("-") && model.unicodeScalars.allSatisfy(modelCharacters.contains)
    }

    private static func isValidToolName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }

    private static func isValidSessionId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }
}
