//
//  ClaudeEvent.swift
//  LF-AIWorkflow
//

nonisolated struct TokenUsage: Sendable, Equatable, Codable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreation: Int

    static let zero = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheCreation: 0)

    /// Tokens that count against a task budget: input + output + cache creation (cache reads excluded).
    var billableTotal: Int { input + output + cacheCreation }

    /// Per-field maximum (usage lines for one message are cumulative).
    func maxing(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(input: max(input, other.input), output: max(output, other.output),
                   cacheRead: max(cacheRead, other.cacheRead), cacheCreation: max(cacheCreation, other.cacheCreation))
    }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead, cacheCreation: lhs.cacheCreation + rhs.cacheCreation)
    }
}

nonisolated struct SessionInit: Sendable, Equatable {
    let sessionId: String
    let model: String?
    let cwd: String?
    let tools: [String]
    let cliVersion: String?
}

nonisolated struct ToolUse: Sendable, Equatable {
    let id: String
    let name: String
    /// Short, capped description of the input (never the full input).
    let inputSummary: String
}

nonisolated struct AssistantMessage: Sendable, Equatable {
    /// Claude repeats one message's id and usage on each content-block line; count usage once per id.
    let messageId: String?
    let texts: [String]
    let toolUses: [ToolUse]
    let usage: TokenUsage?
}

nonisolated struct ToolResult: Sendable, Equatable {
    let toolUseId: String
    let isError: Bool
}

nonisolated struct RunResult: Sendable, Equatable {
    let subtype: String
    let isError: Bool
    let text: String?
    let sessionId: String?
    let numTurns: Int?
    let durationMs: Int?
    let totalCostUSD: Double?
    let usage: TokenUsage
    /// Names of the tools whose use was denied.
    let permissionDenials: [String]
}

nonisolated enum ClaudeEvent: Sendable, Equatable {
    case initialized(SessionInit)
    case assistant(AssistantMessage)
    case toolResult(ToolResult)
    case result(RunResult)
    /// A well-formed line of a type the app ignores (`system/<subtype>`, `rate_limit_event`, ...).
    case unknown(type: String)
    /// A non-JSON pty line (stderr text), capped.
    case unparsed(String)
    /// Emitted by `ClaudeSession` only.
    case exited(status: Int32)
}
