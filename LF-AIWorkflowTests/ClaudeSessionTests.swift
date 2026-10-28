//
//  ClaudeSessionTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeSessionTests {

    private func fixtureURL(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString)-\(name)")
        try loadFixture(name).write(to: url)
        return url
    }

    private func decoded(_ name: String) throws -> [ClaudeEvent] {
        let framer = try NDJSONFramer()
        let lines = try framer.feed(loadFixture(name)) + framer.finish()
        return lines.compactMap(ClaudeEventDecoder.decode)
    }

    private func collect(_ session: ClaudeSession) async -> [ClaudeEvent] {
        var events: [ClaudeEvent] = []
        for await e in session.events { events.append(e) }
        return events
    }

    private func catFixture(_ name: String, prefix: String = "") throws -> (ProcessInvocation, URL) {
        let url = try fixtureURL(name)
        let inv = PTYProcessTests.shell("cat >/dev/null; \(prefix) cat \"$1\"", stdin: Data("prompt".utf8), args: ["_", url.path])
        return (inv, url)
    }

    @Test func replaysFixtureEventsThenExited() async throws {
        let (inv, url) = try catFixture("claude_tool_use.ndjson")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try ClaudeSession()
        try await session.start(inv)
        let events = await collect(session)
        #expect(events == (try decoded("claude_tool_use.ndjson")) + [.exited(status: 0)])
        let sid = await session.sessionId
        #expect(sid?.isEmpty == false)
        let status = await session.exitStatus
        #expect(status == 0)
        let resultUsage: TokenUsage? = events.compactMap { event -> TokenUsage? in
            if case .result(let r) = event { return r.usage } else { return nil }
        }.last
        #expect(await session.usage == resultUsage)
    }

    @Test func nonJSONLineBecomesUnparsed() async throws {
        let (inv, url) = try catFixture("claude_text.ndjson", prefix: "echo 'warning: stderr text';")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try ClaudeSession()
        try await session.start(inv)
        let events = await collect(session)
        #expect(events.first == .unparsed("warning: stderr text"))
        #expect(events.last == .exited(status: 0))
    }

    @Test func startTwiceThrowsAlreadyStarted() async throws {
        let session = try ClaudeSession()
        try await session.start(PTYProcessTests.shell("true"))
        await #expect(throws: ClaudeSessionError.alreadyStarted) {
            try await session.start(PTYProcessTests.shell("true"))
        }
        _ = await collect(session)
    }

    @Test func spawnFailureThrowsSpawnFailed() async throws {
        let session = try ClaudeSession()
        let inv = ProcessInvocation(executable: URL(fileURLWithPath: "/nonexistent/lf-nope"), arguments: [],
                                    environment: [:], workingDirectory: URL(fileURLWithPath: "/"), stdin: Data())
        await #expect(throws: ClaudeSessionError.spawnFailed(ENOENT)) { try await session.start(inv) }
    }

    @Test func cancelEndsStreamWithExit143() async throws {
        let session = try ClaudeSession()
        try await session.start(PTYProcessTests.shell("sleep 30"))
        await session.cancel()
        let events = await collect(session)
        #expect(events.last == .exited(status: 143))
    }

    @Test func droppingEventsKillsChild() async throws {
        let session = try ClaudeSession()
        try await session.start(PTYProcessTests.shell("echo hello; sleep 30"))
        let pid = try #require(await session.processID)
        for await _ in session.events { break }
        let deadline = ContinuousClock.now + .seconds(3)
        while kill(pid, 0) == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func terminalSnapshotHoldsRawBytes() async throws {
        let session = try ClaudeSession()
        try await session.start(PTYProcessTests.shell("echo raw-bytes-here"))
        _ = await collect(session)
        let snap = await session.terminalSnapshot()
        #expect(String(decoding: snap, as: UTF8.self).contains("raw-bytes-here"))
    }

    @Test func childEnvironmentStripsClaudeCodeVariables() async throws {
        let session = try ClaudeSession()
        var inv = PTYProcessTests.shell("echo \"[$CLAUDECODE|$CLAUDE_CODE_ENTRYPOINT|$KEEP]\"")
        inv = ProcessInvocation(executable: inv.executable, arguments: inv.arguments,
                                environment: ["PATH": "/usr/bin:/bin", "CLAUDECODE": "1",
                                              "CLAUDE_CODE_ENTRYPOINT": "cli", "KEEP": "yes"],
                                workingDirectory: inv.workingDirectory, stdin: Data())
        try await session.start(inv)
        let events = await collect(session)
        #expect(events.first == .unparsed("[||yes]"))
    }

    @Test func authAndProviderVariablesSurvive() async throws {
        let session = try ClaudeSession()
        var inv = PTYProcessTests.shell("echo \"[$CLAUDE_CODE_OAUTH_TOKEN|$CLAUDE_CODE_USE_BEDROCK|$CLAUDE_CODE_USE_VERTEX|$CLAUDE_CODE_SSE_PORT]\"")
        inv = ProcessInvocation(executable: inv.executable, arguments: inv.arguments,
                                environment: ["PATH": "/usr/bin:/bin", "CLAUDE_CODE_OAUTH_TOKEN": "t",
                                              "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_USE_VERTEX": "1",
                                              "CLAUDE_CODE_SSE_PORT": "9"],
                                workingDirectory: inv.workingDirectory, stdin: Data())
        try await session.start(inv)
        let events = await collect(session)
        #expect(events.first == .unparsed("[t|1|1|]"))
    }

    @Test func cancelBeforeStartPreventsSpawn() async throws {
        let session = try ClaudeSession()
        await session.cancel()
        await #expect(throws: ClaudeSessionError.cancelled) {
            try await session.start(PTYProcessTests.shell("sleep 30"))
        }
        #expect(await session.processID == nil)
        let events = await collect(session)
        #expect(events.isEmpty)
    }

    @Test func usageKeepsLatestPerMessageId() async throws {
        func line(_ id: String, _ out: Int) -> String {
            "{\"type\":\"assistant\",\"message\":{\"id\":\"\(id)\",\"content\":[],\"usage\":{\"input_tokens\":10,\"output_tokens\":\(out),\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}"
        }
        let body = [line("m1", 1), line("m1", 50), line("m2", 7)].joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString).ndjson")
        try Data((body + "\n").utf8).write(to: url)
        let session = try ClaudeSession()
        try await session.start(PTYProcessTests.shell("cat \"$1\"", args: ["_", url.path]))
        _ = await collect(session)
        let usage = await session.usage
        #expect(usage.output == 57)
        #expect(usage.input == 20)
    }
}
