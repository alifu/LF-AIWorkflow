//
//  DraftTitle.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum DraftTitle {
    static let maxLength = 60
    static let placeholder = "Untitled task"

    /// First non-empty line of the prompt, trimmed, capped at `maxLength` characters ("Untitled task" when empty).
    /// Complexity: O(n) time in the prompt length, O(maxLength) space
    static func derive(from prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine else { return placeholder }
        return String(firstLine.prefix(maxLength))
    }
}
