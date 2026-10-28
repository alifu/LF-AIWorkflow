//
//  ClaudeSessionIntegrationTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

enum ClaudeIntegration {
    static let environment = ProcessInfo.processInfo.environment
    static var searchPath: [String] {
        ToolLocator.searchPath(loginShellPATH: nil, processPATH: environment["PATH"], home: NSHomeDirectory())
    }
    static var claudeURL: URL? { try? ToolLocator(searchPath: searchPath).locate(.claude) }
    /// Opt-in: `TEST_RUNNER_LF_RUN_CLAUDE_TESTS=1 xcodebuild ... test` and `claude` installed.
    static var isEnabled: Bool { environment["LF_RUN_CLAUDE_TESTS"] == "1" && claudeURL != nil }
}

@Suite(.tags(.requiresClaude), .enabled(if: ClaudeIntegration.isEnabled), .serialized, .timeLimit(.minutes(2)))
struct ClaudeSessionIntegrationTests {

    @Test func realCLIRoundTripYieldsInitAndResult() async throws {
        let claude = try #require(ClaudeIntegration.claudeURL)
        let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("lf-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cwd) }

        let config = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default, allowedTools: [],
                                 disallowedTools: StagePolicy.alwaysDenied, maxTurns: 1)
        let invocation = try ClaudeCommandBuilder.invocation(
            executable: claude, config: config, sessionId: nil, addDirs: [], workingDirectory: cwd,
            prompt: "say ok", baseEnvironment: ClaudeIntegration.environment, searchPath: ClaudeIntegration.searchPath)

        let session = try ClaudeSession()
        try await session.start(invocation)
        let watchdog = Task { try await Task.sleep(for: .seconds(90)); await session.cancel() }
        defer { watchdog.cancel() }

        var events: [ClaudeEvent] = []
        for await event in session.events { events.append(event) }

        let initialized = events.compactMap { event -> SessionInit? in
            if case .initialized(let info) = event { info } else { nil }
        }.first
        #expect(initialized?.sessionId.isEmpty == false)
        let results = events.compactMap { event -> RunResult? in
            if case .result(let r) = event { r } else { nil }
        }
        #expect(results.count == 1)
        #expect(results.first?.isError == false)
        #expect(events.last == .exited(status: 0))
    }
}
