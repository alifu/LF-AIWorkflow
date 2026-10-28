//
//  ClaudeEventDecoder.swift
//  LF-AIWorkflow
//

import Foundation

/// Tolerant decoder for one stream-JSON line (R3): unknown types and fields never fail a run.
nonisolated enum ClaudeEventDecoder {
    static let maxUnparsedLength = 2048
    static let maxInputSummaryLength = 200

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let space = UInt8(ascii: " ")
    private static let openBrace = UInt8(ascii: "{")

    /// Nil for blank lines. Never throws.
    /// Complexity: O(n) time, O(n) space (n = line length)
    static func decode(_ line: Data) -> ClaudeEvent? {
        let trimmed = trim(line)
        guard let first = trimmed.first else { return nil }
        guard first == openBrace else { return unparsed(trimmed) }
        guard let type = NDJSONFramer.field("type", in: trimmed) else {
            return isJSONObject(trimmed) ? .unknown(type: "") : unparsed(trimmed)
        }
        let decoder = JSONDecoder()
        switch type {
        case "system":
            guard NDJSONFramer.field("subtype", in: trimmed) == "init" else {
                return .unknown(type: "system/" + (NDJSONFramer.field("subtype", in: trimmed) ?? ""))
            }
            guard let dto = try? decoder.decode(InitDTO.self, from: trimmed), let sid = dto.session_id else {
                return unparsed(trimmed)
            }
            return .initialized(SessionInit(sessionId: sid, model: dto.model, cwd: dto.cwd,
                                            tools: dto.tools ?? [], cliVersion: dto.claude_code_version))
        case "assistant":
            guard let dto = try? decoder.decode(AssistantLineDTO.self, from: trimmed) else { return unparsed(trimmed) }
            return .assistant(assistantMessage(dto.message))
        case "user":
            guard let dto = try? decoder.decode(UserLineDTO.self, from: trimmed) else { return unparsed(trimmed) }
            guard let block = dto.message?.content?.first(where: { $0.type == "tool_result" }),
                  let id = block.tool_use_id else { return .unknown(type: "user") }
            return .toolResult(ToolResult(toolUseId: id, isError: block.is_error ?? false))
        case "result":
            guard let dto = try? decoder.decode(ResultDTO.self, from: trimmed) else { return unparsed(trimmed) }
            return .result(RunResult(
                subtype: dto.subtype ?? "", isError: dto.is_error ?? false, text: dto.result,
                sessionId: dto.session_id, numTurns: dto.num_turns, durationMs: dto.duration_ms,
                totalCostUSD: dto.total_cost_usd, usage: dto.usage.map(tokenUsage) ?? .zero,
                permissionDenials: dto.permission_denials?.compactMap(\.tool_name) ?? []))
        default:
            return .unknown(type: type)
        }
    }

    // MARK: helpers

    /// Strips a trailing `\r`/`\n`/space run and leading spaces.
    private static func trim(_ line: Data) -> Data {
        var slice = line[...]
        while let last = slice.last, last == carriageReturn || last == newline || last == space { slice = slice.dropLast() }
        while let head = slice.first, head == space { slice = slice.dropFirst() }
        return Data(slice)
    }

    private static func isJSONObject(_ line: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: line)) is [String: Any]
    }

    private static func unparsed(_ line: Data) -> ClaudeEvent {
        .unparsed(String(decoding: line.prefix(maxUnparsedLength), as: UTF8.self))
    }

    private static func tokenUsage(_ dto: UsageDTO) -> TokenUsage {
        TokenUsage(input: dto.input_tokens ?? 0, output: dto.output_tokens ?? 0,
                   cacheRead: dto.cache_read_input_tokens ?? 0, cacheCreation: dto.cache_creation_input_tokens ?? 0)
    }

    private static func assistantMessage(_ message: AssistantBodyDTO?) -> AssistantMessage {
        var texts: [String] = []
        var toolUses: [ToolUse] = []
        for block in message?.content ?? [] {
            switch block.type {
            case "text":
                if let text = block.text { texts.append(text) }
            case "tool_use":
                if let id = block.id, let name = block.name {
                    toolUses.append(ToolUse(id: id, name: name, inputSummary: summary(of: block.input)))
                }
            default:
                break
            }
        }
        return AssistantMessage(messageId: message?.id, texts: texts, toolUses: toolUses,
                                usage: message?.usage.map(tokenUsage))
    }

    private static let preferredInputKeys = ["file_path", "command", "pattern", "path", "url", "query", "description"]

    /// One short line: the most telling string argument, else the argument names. Capped.
    /// Complexity: O(k) time, O(k) space
    private static func summary(of input: [String: JSONValue]?) -> String {
        guard let input, !input.isEmpty else { return "" }
        for key in preferredInputKeys {
            if case .string(let value)? = input[key] { return String(value.prefix(maxInputSummaryLength)) }
        }
        return String(input.keys.sorted().joined(separator: ",").prefix(maxInputSummaryLength))
    }
}

// MARK: DTOs (all fields optional)

private nonisolated struct InitDTO: Decodable {
    let session_id: String?
    let model: String?
    let cwd: String?
    let tools: [String]?
    let claude_code_version: String?
}

private nonisolated struct UsageDTO: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}

private nonisolated struct AssistantLineDTO: Decodable {
    let message: AssistantBodyDTO?
}

private nonisolated struct AssistantBodyDTO: Decodable {
    let id: String?
    let content: [AssistantBlockDTO]?
    let usage: UsageDTO?
}

private nonisolated struct AssistantBlockDTO: Decodable {
    let type: String?
    let text: String?
    let id: String?
    let name: String?
    let input: [String: JSONValue]?
}

private nonisolated struct UserLineDTO: Decodable {
    let message: UserBodyDTO?
}

/// `content` is a plain string for ordinary user turns; only the block-array form matters.
private nonisolated struct UserBodyDTO: Decodable {
    let content: [UserBlockDTO]?

    enum CodingKeys: String, CodingKey { case content }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try? container.decode([UserBlockDTO].self, forKey: .content)
    }
}

private nonisolated struct UserBlockDTO: Decodable {
    let type: String?
    let tool_use_id: String?
    let is_error: Bool?
}

private nonisolated struct DenialDTO: Decodable {
    let tool_name: String?
}

private nonisolated struct ResultDTO: Decodable {
    let subtype: String?
    let is_error: Bool?
    let result: String?
    let session_id: String?
    let num_turns: Int?
    let duration_ms: Int?
    let total_cost_usd: Double?
    let usage: UsageDTO?
    let permission_denials: [DenialDTO]?
}

/// Minimal JSON tree so tool inputs of any shape decode without failing.
private nonisolated enum JSONValue: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { self = .string(string) } else { self = .other }
    }
}
