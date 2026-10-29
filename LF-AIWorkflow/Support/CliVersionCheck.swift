//
//  CliVersionCheck.swift
//  LF-AIWorkflow
//

import Foundation

/// Compares the installed Claude CLI with the version the stream-JSON fixtures were recorded against (TD-003).
/// Refreshing the fixtures stays manual; this only warns.
nonisolated enum CliVersionCheck {
    /// Keep in step with `Fixtures/claude/claude_fixtures_version.txt`.
    static let pinnedClaudeVersion = "2.1.312"

    /// The first dotted-number token in the text (e.g. `2.1.312` from `2.1.312 (Claude Code)`).
    /// Complexity: O(n) time, O(n) space
    static func version(in text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .first { token in
                token.contains(".") && token.allSatisfy { $0.isNumber || $0 == "." } && token.first?.isNumber == true
            }
    }

    /// A user-facing warning when the reported version differs from the pinned one; nil when equal or unparsable.
    /// Complexity: O(n) time, O(n) space
    static func warning(forVersionLine line: String) -> String? {
        guard let found = version(in: line), found != pinnedClaudeVersion else { return nil }
        return "Claude CLI \(found) differs from \(pinnedClaudeVersion), the version the output parser was tested "
            + "against. Output may not be understood correctly."
    }
}
