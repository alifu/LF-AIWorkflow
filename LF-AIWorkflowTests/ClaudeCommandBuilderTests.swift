//
//  ClaudeCommandBuilderTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ClaudeCommandBuilderTests {
    private let policy = StagePolicy.defaults(testCommand: "scripts/check.sh")

    private func expectedArguments(_ c: StageConfig, resume: String? = nil, dirs: [String] = []) -> [String] {
        var a = ["-p", "--output-format", "stream-json", "--verbose", "--model", c.model,
                 "--max-turns", String(c.maxTurns), "--permission-mode", c.permissionMode.rawValue]
        if let t = c.builtinTools { a += ["--tools", t.joined(separator: ",")] }
        a += c.isolated ? ["--strict-mcp-config", "--setting-sources", "project", "--disable-slash-commands"]
                        : ["--strict-mcp-config", "--setting-sources", "user"]
        if !c.allowedTools.isEmpty { a += ["--allowedTools", c.allowedTools.joined(separator: ",")] }
        if !c.disallowedTools.isEmpty { a += ["--disallowedTools", c.disallowedTools.joined(separator: ",")] }
        for d in dirs { a += ["--add-dir", d] }
        if let resume { a += ["--resume", resume] }
        return a
    }

    @Test(arguments: WorkflowStage.allCases)
    func exactArgumentsPerStage(stage: WorkflowStage) throws {
        let config = policy.config(for: stage)
        #expect(try ClaudeCommandBuilder.arguments(config: config, sessionId: nil, addDirs: []) == expectedArguments(config))
    }

    private let sid0 = "3f2b8c1e-5a4d-4e7f-9b6a-1c2d3e4f5a6b"

    @Test func resumeAndMultipleAddDirs() throws {
        let config = policy.config(for: .code)
        let dirs = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b/../c")]
        let args = try ClaudeCommandBuilder.arguments(config: config, sessionId: sid0, addDirs: dirs)
        #expect(args == expectedArguments(config, resume: sid0, dirs: ["/tmp/a", "/tmp/c"]))
    }

    @Test func toolListsStayOneArgument() throws {
        let config = policy.config(for: .review)
        let args = try ClaudeCommandBuilder.arguments(config: config, sessionId: nil, addDirs: [])
        let i = try #require(args.firstIndex(of: "--allowedTools"))
        #expect(args[i + 1] == "Read,Grep,Glob,Bash(git diff:*)")
    }

    @Test(arguments: WorkflowStage.allCases)
    func projectAndLocalSettingsAndMcpAreNeverLoaded(stage: WorkflowStage) throws {
        let args = try ClaudeCommandBuilder.arguments(config: policy.config(for: stage), sessionId: nil, addDirs: [])
        #expect(args.contains("--strict-mcp-config"))
        let i = try #require(args.firstIndex(of: "--setting-sources"))
        #expect(args[i + 1] == "user")
    }

    @Test func reviewHasExplicitReadOnlyToolList() throws {
        let args = try ClaudeCommandBuilder.arguments(config: policy.config(for: .review), sessionId: nil, addDirs: [])
        let i = try #require(args.firstIndex(of: "--tools"))
        #expect(args[i + 1] == "Read,Grep,Glob,Bash")
    }

    @Test func emptyToolListsOmitFlags() throws {
        let config = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default,
                                 allowedTools: [], disallowedTools: [], maxTurns: 1)
        let args = try ClaudeCommandBuilder.arguments(config: config, sessionId: nil, addDirs: [])
        #expect(!args.contains("--allowedTools") && !args.contains("--disallowedTools"))
    }

    private func config(model: String = "haiku", turns: Int = 1) -> StageConfig {
        StageConfig(model: model, escalationModel: nil, permissionMode: .default, allowedTools: [], disallowedTools: [], maxTurns: turns)
    }

    @Test(arguments: ["", "-x", "a b", "a;b", "a\nb", "$(x)"])
    func invalidModelThrows(model: String) {
        #expect(throws: ClaudeCommandError.invalidModel(model)) {
            try ClaudeCommandBuilder.arguments(config: config(model: model), sessionId: nil, addDirs: [])
        }
    }

    @Test(arguments: ["opus", "claude-opus-4-1", "sonnet[1m]", "a.b_c"])
    func validModelsPass(model: String) throws {
        _ = try ClaudeCommandBuilder.arguments(config: config(model: model), sessionId: nil, addDirs: [])
    }

    @Test(arguments: [0, 101, -1])
    func invalidMaxTurnsThrows(turns: Int) {
        #expect(throws: ClaudeCommandError.invalidMaxTurns(turns)) {
            try ClaudeCommandBuilder.arguments(config: config(turns: turns), sessionId: nil, addDirs: [])
        }
    }

    @Test(arguments: ["", "a b", "--x ", "a/b", "--dangerously-skip-permissions", "-3f2b8c1e-5a4d-4e7f-9b6a-1c2d3e4f5a6", "abc-123", "3f2b8c1e-5a4d-4e7f-9b6a-1c2d3e4f5a6b ", String(repeating: "a", count: 129)])
    func invalidSessionIdThrows(sid: String) {
        #expect(throws: ClaudeCommandError.invalidSessionId(sid)) {
            try ClaudeCommandBuilder.arguments(config: config(), sessionId: sid, addDirs: [])
        }
    }

    @Test func relativeDirectoryThrows() {
        let relative = URL(string: "relative/dir")!
        #expect(throws: ClaudeCommandError.relativeDirectory("relative/dir")) {
            try ClaudeCommandBuilder.arguments(config: config(), sessionId: nil, addDirs: [relative])
        }
    }

    @Test func environmentCleansAndSetsPath() {
        let base = ["HOME": "/Users/x", "PATH": "/old", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli",
                    "CLAUDE_CODE_SSE_PORT": "1234", "CLAUDE_CODE_OAUTH_TOKEN": "tok",
                    "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_USE_VERTEX": "1"]
        let env = ClaudeCommandBuilder.environment(base: base, searchPath: ["/a", "/b"])
        #expect(env["HOME"] == "/Users/x")
        #expect(env["PATH"] == "/a:/b")
        for key in ClaudeCommandBuilder.droppedEnvironmentKeys { #expect(env[key] == nil) }
        #expect(ClaudeCommandBuilder.droppedEnvironmentKeys.isSuperset(of: ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"]))
        #expect(env["CLAUDE_CODE_OAUTH_TOKEN"] == "tok")
        #expect(env["CLAUDE_CODE_USE_BEDROCK"] == "1" && env["CLAUDE_CODE_USE_VERTEX"] == "1")
        #expect(env["TERM"] == "dumb" && env["NO_COLOR"] == "1")
    }

    @Test func toolRuleWithCommaIsRejected() {
        let c = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default,
                            allowedTools: ["Bash(xcodebuild -only-testing:A,B)"], disallowedTools: [], maxTurns: 1)
        #expect(throws: ClaudeCommandError.invalidToolRule("Bash(xcodebuild -only-testing:A,B)")) {
            try ClaudeCommandBuilder.arguments(config: c, sessionId: nil, addDirs: [])
        }
        let d = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default,
                            allowedTools: [], disallowedTools: ["a,b"], maxTurns: 1)
        #expect(throws: ClaudeCommandError.invalidToolRule("a,b")) {
            try ClaudeCommandBuilder.arguments(config: d, sessionId: nil, addDirs: [])
        }
    }

    @Test func promptGoesToStdinNeverArgv() throws {
        let prompt = "SECRET prompt text --model evil"
        let inv = try ClaudeCommandBuilder.invocation(
            executable: URL(fileURLWithPath: "/bin/claude"), config: policy.config(for: .plan), sessionId: nil, addDirs: [],
            workingDirectory: URL(fileURLWithPath: "/tmp"), prompt: prompt, baseEnvironment: ["HOME": "/h"], searchPath: ["/usr/bin"])
        #expect(inv.stdin == Data(prompt.utf8))
        #expect(!inv.arguments.contains { $0.contains("SECRET") })
        #expect(inv.executable.path == "/bin/claude" && inv.workingDirectory.path == "/tmp")
        #expect(inv.environment["PATH"] == "/usr/bin")
    }
}
