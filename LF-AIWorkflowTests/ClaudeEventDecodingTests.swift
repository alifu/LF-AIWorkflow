//
//  ClaudeEventDecodingTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ClaudeEventDecodingTests {
    /// Feeds data through the real framer in 7-byte chunks, decoding each line.
    private func decodeAll(_ data: Data) throws -> [ClaudeEvent] {
        let framer = try NDJSONFramer()
        var lines: [Data] = []
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: 7, limitedBy: data.endIndex) ?? data.endIndex
            lines += try framer.feed(data[index..<end])
            index = end
        }
        lines += try framer.finish()
        return lines.flatMap(ClaudeEventDecoder.decode)
    }

    private func fixture(_ name: String) throws -> [ClaudeEvent] { try decodeAll(loadFixture(name)) }

    private func initEvent(_ events: [ClaudeEvent]) -> SessionInit? {
        for case .initialized(let i) in events { return i }
        return nil
    }

    private func result(_ events: [ClaudeEvent]) -> RunResult? {
        for case .result(let r) in events.reversed() { return r }
        return nil
    }

    // MARK: hand-written

    @Test func blankLinesDecodeToNoEvents() {
        #expect(ClaudeEventDecoder.decode(Data()).isEmpty)
        #expect(ClaudeEventDecoder.decode(Data("  \r".utf8)).isEmpty)
    }

    @Test func everyToolResultBlockOnOneUserLineYieldsItsOwnEvent() {
        let line = Data("{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hi\"},{\"type\":\"tool_result\",\"tool_use_id\":\"a\",\"is_error\":false},{\"type\":\"tool_result\",\"tool_use_id\":\"b\",\"is_error\":true}]}}".utf8)
        #expect(ClaudeEventDecoder.decode(line) == [
            .toolResult(ToolResult(toolUseId: "a", isError: false)),
            .toolResult(ToolResult(toolUseId: "b", isError: true)),
        ])
    }

    @Test func edgeCasesDecodeWithoutCrash() throws {
        let events = try fixture("claude_edge_cases.ndjson")
        #expect(events.count == 9)  // blank line dropped
        #expect(events[0] == .unknown(type: "brand_new_event"))
        guard case .assistant(let nested) = events[1] else { Issue.record("expected assistant"); return }
        #expect(nested.texts == ["he said \"{\\\"type\\\":\\\"result\\\"}\" ok"])
        #expect(nested.usage == nil)
        #expect(events[2] == .unparsed("this is plain stderr text, not json"))
        guard case .assistant(let noUsage) = events[3] else { Issue.record("expected assistant"); return }
        #expect(noUsage.texts == ["no usage here"] && noUsage.usage == nil)
        #expect(events[4] == .unknown(type: "system/something_new"))
        guard case .result(let r) = events[5] else { Issue.record("expected result"); return }
        #expect(r.subtype == "success" && !r.isError && r.usage == .zero && r.permissionDenials.isEmpty)
        guard case .unparsed = events[6] else { Issue.record("expected unparsed for truncated JSON"); return }
        #expect(events[7] == .unknown(type: ""))
        #expect(events[8] == .unknown(type: "user"))
    }

    @Test func carriageReturnIsTolerated() {
        let events = ClaudeEventDecoder.decode(Data("{\"type\":\"rate_limit_event\"}\r".utf8))
        #expect(events == [.unknown(type: "rate_limit_event")])
    }

    @Test func oneMegabyteTextDecodes() throws {
        let big = String(repeating: "x", count: 1_000_000)
        let line = Data("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"\(big)\"}]}}".utf8)
        guard case .assistant(let m)? = ClaudeEventDecoder.decode(line).first else { Issue.record("expected assistant"); return }
        #expect(m.texts.first?.count == 1_000_000)
    }

    @Test func unparsedTextIsCapped() {
        let long = String(repeating: "e", count: 10_000)
        guard case .unparsed(let text)? = ClaudeEventDecoder.decode(Data(long.utf8)).first else { Issue.record("expected unparsed"); return }
        #expect(text.count == 2048)
    }

    @Test func toolInputSummaryIsCapped() {
        let long = String(repeating: "p", count: 5000)
        let line = Data("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Read\",\"input\":{\"file_path\":\"\(long)\"}}]}}".utf8)
        guard case .assistant(let m)? = ClaudeEventDecoder.decode(line).first else { Issue.record("expected assistant"); return }
        #expect(m.toolUses.first?.inputSummary.count == 200)
    }

    @Test func tokenUsageAdds() {
        let a = TokenUsage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
        #expect(a + a == TokenUsage(input: 2, output: 4, cacheRead: 6, cacheCreation: 8))
        #expect(a + .zero == a)
    }

    // MARK: recorded

    @Test(arguments: ["claude_text", "claude_tool_use", "claude_resume", "claude_max_turns", "claude_denied"])
    func recordedStreamStartsWithInitAndEndsWithResult(name: String) throws {
        let events = try fixture(name + ".ndjson")
        let first = try #require(initEvent(events))
        #expect(!first.sessionId.isEmpty)
        let jsonEvents = events.filter { if case .unparsed = $0 { false } else { true } }
        guard case .result? = jsonEvents.last else { Issue.record("last event is not result"); return }
        #expect(!events.contains { if case .unparsed = $0 { true } else { false } })
        // Hooks, rate limits and thinking_tokens are tolerated as unknown.
        #expect(events.contains { if case .unknown = $0 { true } else { false } })
        #expect(first.cliVersion == "2.1.312")
    }

    @Test func toolUseHasMatchingToolResult() throws {
        let events = try fixture("claude_tool_use.ndjson")
        var use: ToolUse?
        for case .assistant(let m) in events { if let t = m.toolUses.first { use = t } }
        let tool = try #require(use)
        #expect(tool.name == "Read" && tool.inputSummary.hasSuffix("hello.txt"))
        let results = events.compactMap { event -> ToolResult? in if case .toolResult(let r) = event { r } else { nil } }
        #expect(results == [ToolResult(toolUseId: tool.id, isError: false)])
    }

    @Test func resumeKeepsSessionId() throws {
        let text = try #require(initEvent(fixture("claude_text.ndjson")))
        let resume = try #require(initEvent(fixture("claude_resume.ndjson")))
        #expect(text.sessionId == resume.sessionId)
    }

    @Test func maxTurnsResultIsError() throws {
        let r = try #require(result(fixture("claude_max_turns.ndjson")))
        #expect(r.subtype == "error_max_turns" && r.isError)
    }

    @Test func deniedResultListsWrite() throws {
        let events = try fixture("claude_denied.ndjson")
        let r = try #require(result(events))
        #expect(r.permissionDenials.contains("Write"))
        #expect(events.contains(.toolResult(ToolResult(toolUseId: toolUseIdOfWrite(events), isError: true))))
    }

    private func toolUseIdOfWrite(_ events: [ClaudeEvent]) -> String {
        for case .assistant(let m) in events { if let t = m.toolUses.first(where: { $0.name == "Write" }) { return t.id } }
        return ""
    }

    @Test func badModelIsAnErrorNeverSuccess() throws {
        let events = try fixture("claude_bad_model.ndjson")
        let r = try #require(result(events))
        #expect(r.isError && r.text?.contains("not-a-real-model") == true)
        let stderr = try fixture("claude_bad_model.stderr")
        guard case .unparsed(let text)? = stderr.first else { Issue.record("expected unparsed stderr"); return }
        #expect(text.hasPrefix("[claude-code:unrecognized_model]"))
    }

    @Test func resultUsageMatchesFixtureAndAssistantSums() throws {
        for name in ["claude_text", "claude_tool_use", "claude_resume"] {
            let events = try fixture(name + ".ndjson")
            let r = try #require(result(events))
            // Assistant lines repeat a message's usage per content block; count each message once.
            var seen = Set<String>()
            var sum = TokenUsage.zero
            for case .assistant(let m) in events {
                guard let usage = m.usage, let id = m.messageId, seen.insert(id).inserted else { continue }
                sum = sum + usage
            }
            #expect(sum.input == r.usage.input)
            #expect(sum.cacheRead == r.usage.cacheRead)
            #expect(sum.cacheCreation == r.usage.cacheCreation)
            #expect(r.usage.output >= sum.output)  // result adds thinking tokens
        }
        let toolUse = try #require(result(fixture("claude_tool_use.ndjson")))
        #expect(toolUse.usage == TokenUsage(input: 4, output: 278, cacheRead: 54305, cacheCreation: 31331))
        #expect(toolUse.numTurns != nil && toolUse.durationMs != nil && toolUse.totalCostUSD != nil)
    }
}
