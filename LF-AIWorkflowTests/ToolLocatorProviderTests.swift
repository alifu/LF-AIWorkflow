//
//  ToolLocatorProviderTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

/// Mutable overrides standing in for the Settings store.
private final class OverrideBox: Sendable {
    private let paths = OSAllocatedUnfairLock(initialState: [Tool: String]())
    func set(_ tool: Tool, _ path: String) { paths.withLock { $0[tool] = path } }
    var provider: ToolLocatorProvider {
        ToolLocatorProvider { [paths] in ToolLocator(searchPath: [], overrides: paths.withLock { $0 }) }
    }
}

struct ToolLocatorProviderTests {
    private func script(_ name: String, body: String) throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lf-tlp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try TestEnv.writeScript(file, contents: body, mode: 0o755)
        return (dir, file)
    }

    @Test func gitClientUsesThePathSetAfterConstruction() async throws {
        let a = try script("git", body: "#!/bin/sh\necho first\n")
        let b = try script("git", body: "#!/bin/sh\necho second\n")
        defer { try? FileManager.default.removeItem(at: a.dir); try? FileManager.default.removeItem(at: b.dir) }
        let box = OverrideBox()
        box.set(.git, a.file.path)
        let git = GitClient(locators: box.provider)
        let first = try await git.run(["x"], in: a.dir)
        box.set(.git, b.file.path)
        let second = try await git.run(["x"], in: a.dir)
        #expect(first.contains("first"))
        #expect(second.contains("second"))
    }

    @Test func claudeRunnerReportsTheCurrentPathEachRun() async {
        let box = OverrideBox()
        let runner = LiveClaudeRunner(locators: box.provider, baseEnvironment: [:], searchPath: [])
        box.set(.claude, "/nonexistent/one")
        let first = await failure(runner)
        box.set(.claude, "/nonexistent/two")
        let second = await failure(runner)
        #expect(first == .overrideNotExecutable(.claude, path: "/nonexistent/one"))
        #expect(second == .overrideNotExecutable(.claude, path: "/nonexistent/two"))
    }

    private func failure(_ runner: LiveClaudeRunner) async -> ToolLocatorError? {
        let config = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default,
                                 allowedTools: [], disallowedTools: [], maxTurns: 1)
        let request = ResearchRunRequest(
            stage: .analyze, config: config, prompt: "p", sessionId: nil,
            workingDirectory: FileManager.default.temporaryDirectory)
        do { for try await _ in runner.run(request) {} } catch { return error as? ToolLocatorError }
        return nil
    }
}
