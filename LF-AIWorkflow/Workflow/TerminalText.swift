//
//  TerminalText.swift
//  LF-AIWorkflow
//

import Foundation

/// Pure helpers for the read-only activity log pane.
nonisolated enum TerminalText {
    static let defaultTail = 300

    /// The newest `limit` lines.
    /// Complexity: O(limit) time, O(limit) space
    static func tail(_ lines: [TaskLogLine], limit: Int = defaultTail) -> [TaskLogLine] {
        guard limit > 0 else { return [] }
        return Array(lines.suffix(limit))
    }

    /// Plain text for the Copy button (all given lines, one per line).
    /// Complexity: O(n) time, O(n) space
    static func copyText(_ lines: [TaskLogLine]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }
}
