//
//  ClaudeStageRunnerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(2)))
struct ClaudeStageRunnerTests {
    private let policy = StagePolicy.defaults(testCommand: nil)

    /// A fake `claude` that drains stdin, then runs `body`. Returns (runner, scratch dir).
    private func fake(_ body: String) throws -> (runner: ClaudeStageRunner, dir: URL) {
        let dir = try TestEnv.makeTempDir()
        let exe = try TestEnv.writeExecutable(dir, "claude", body: "cat >/dev/null\n" + body)
        return (ClaudeStageRunner(executable: exe, baseEnvironment: ["HOME": dir.path], searchPath: ["/usr/bin", "/bin"]), dir)
    }

    private func replaying(_ fixture: String) throws -> (runner: ClaudeStageRunner, dir: URL) {
        let dir = try TestEnv.makeTempDir()
        let data = dir.appendingPathComponent(fixture)
        try loadFixture(fixture).write(to: data)
        let exe = try TestEnv.writeExecutable(dir, "claude", body: "cat >/dev/null\ncat \"\(data.path)\"")
        return (ClaudeStageRunner(executable: exe, baseEnvironment: ["HOME": dir.path], searchPath: ["/usr/bin", "/bin"]), dir)
    }

    private func request(_ stage: WorkflowStage = .code, config: StageConfig? = nil, dir: URL) -> StageRunRequest {
        StageRunRequest(stage: stage, config: config ?? policy.config(for: stage), prompt: "do it", sessionId: nil,
                        addDirs: [], workingDirectory: dir)
    }

    private func collect(_ stream: AsyncThrowingStream<StageRunEvent, Error>) async throws -> [StageRunEvent] {
        var events: [StageRunEvent] = []
        for try await e in stream { events.append(e) }
        return events
    }

    private func finished(_ events: [StageRunEvent]) -> [StageRunOutcome] {
        events.compactMap { if case .finished(let o) = $0 { o } else { nil } }
    }

    private func decodedResult(_ fixture: String) throws -> RunResult {
        let framer = try NDJSONFramer()
        let lines = try framer.feed(loadFixture(fixture)) + framer.finish()
        for case .result(let r) in lines.compactMap(ClaudeEventDecoder.decode) { return r }
        throw CocoaError(.fileReadCorruptFile)
    }

    @Test func textFixtureEndsWithOneFinishedCarryingSessionAndUsage() async throws {
        let (runner, dir) = try replaying("claude_text.ndjson")
        defer { try? FileManager.default.removeItem(at: dir) }
        let events = try await collect(runner.run(request(dir: dir)))
        let expected = try decodedResult("claude_text.ndjson")
        let outcomes = finished(events)
        #expect(outcomes.count == 1)
        #expect(events.last == .finished(try #require(outcomes.first)))
        #expect(outcomes.first?.sessionId == expected.sessionId)
        #expect(outcomes.first?.usage == expected.usage)
        #expect(outcomes.first?.text == expected.text)
        #expect(outcomes.first?.isError == false)
        #expect(events.contains { if case .usage = $0 { true } else { false } })
    }

    @Test func usageEventsReportTheRunningTotal() async throws {
        let (runner, dir) = try replaying("claude_text.ndjson")
        defer { try? FileManager.default.removeItem(at: dir) }
        let events = try await collect(runner.run(request(dir: dir)))
        let totals = events.compactMap { if case .usage(let u) = $0 { u } else { nil } }
        #expect(!totals.isEmpty)
        #expect(totals.allSatisfy { $0.output > 0 || $0.input > 0 || $0.cacheCreation > 0 })
    }

    @Test func toolUseProducesCappedActivity() async throws {
        let (runner, dir) = try replaying("claude_tool_use.ndjson")
        defer { try? FileManager.default.removeItem(at: dir) }
        let events = try await collect(runner.run(request(dir: dir)))
        let activities = events.compactMap { if case .activity(let a) = $0 { a } else { nil } }
        #expect(!activities.isEmpty)
        #expect(activities.allSatisfy { $0.count <= 200 && !$0.isEmpty })
    }

    @Test func maxTurnsFixtureIsAnError() async throws {
        let (runner, dir) = try replaying("claude_max_turns.ndjson")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try #require(finished(try await collect(runner.run(request(dir: dir)))).first)
        #expect(outcome.isError)
    }

    @Test func permissionDenialsAreReported() async throws {
        let (runner, dir) = try replaying("claude_denied.ndjson")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = try #require(finished(try await collect(runner.run(request(dir: dir)))).first)
        #expect(outcome.permissionDenials == (try decodedResult("claude_denied.ndjson")).permissionDenials)
    }

    @Test func exitWithoutResultIsAnErrorWithStatus() async throws {
        let (runner, dir) = try fake("exit 1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let events = try await collect(runner.run(request(dir: dir)))
        let outcomes = finished(events)
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.isError == true)
        #expect(outcomes.first?.exitStatus == 1)
    }

    @Test func commaToolRuleThrowsAndSpawnsNothing() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("spawned")
        let exe = try TestEnv.writeExecutable(dir, "claude", body: "touch \"\(marker.path)\"")
        let runner = ClaudeStageRunner(executable: exe, baseEnvironment: [:], searchPath: ["/usr/bin", "/bin"])
        let base = policy.config(for: .code)
        let bad = StageConfig(model: base.model, escalationModel: nil, permissionMode: base.permissionMode,
                              allowedTools: ["Bash(xcodebuild -only-testing:A,B)"], disallowedTools: [], maxTurns: 5)
        do {
            _ = try await collect(runner.run(request(config: bad, dir: dir)))
            Issue.record("expected throw")
        } catch {
            #expect(error as? ClaudeCommandError == .invalidToolRule("Bash(xcodebuild -only-testing:A,B)"))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func cancellingTheConsumerKillsTheChild() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appendingPathComponent("pid")
        let (runner, scratch) = try fake("echo $$ > \"\(pidFile.path)\"\nexec sleep 30")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let consumer = Task { try await collect(runner.run(request(dir: dir))) }
        let pid = try #require(try await TestEnv.readPid(pidFile, attempts: 400))
        consumer.cancel()
        _ = try? await consumer.value
        #expect(try await TestEnv.waitUntilGone(pid), "child survived consumer cancellation")
    }
}
