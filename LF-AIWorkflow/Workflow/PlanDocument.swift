//
//  PlanDocument.swift
//  LF-AIWorkflow
//

import Foundation

/// A plan file reduced to what the approval and plan views show.
nonisolated struct PlanDocument: Sendable, Equatable {
    static let maxBytes = 200 * 1024

    let path: URL
    let steps: [String]
    let estimatedTokens: Int
    let isTruncated: Bool

    /// Steps come from `## Step ...` headings when there are any, else from numbered (`1.` / `1)`) or checklist
    /// (`- [ ]` / `- [x]`) items at the top level. Tolerates CRLF and blank files.
    /// Complexity: O(n) time, O(s) space (s = steps)
    static func parse(_ markdown: String, path: URL, isTruncated: Bool = false) -> PlanDocument {
        var headings: [String] = []
        var items: [String] = []
        for line in markdown.split(whereSeparator: \.isNewline) {
            if let heading = stepHeading(line) { headings.append(heading) } else if let item = listItem(line) { items.append(item) }
        }
        return PlanDocument(path: path, steps: headings.isEmpty ? items : headings,
                            estimatedTokens: TokenEstimator.estimate(markdown), isTruncated: isTruncated)
    }

    private static let maxIndent = 1

    /// `## Step 3: Title` (any heading level 2 to 4 whose text starts with "Step").
    private static func stepHeading(_ line: Substring) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (2...4).contains(hashes.count) else { return nil }
        let text = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasPrefix("step"), !text.isEmpty else { return nil }
        return text
    }

    /// `1. text`, `1) text`, `- [ ] text`, `- [x] text` with at most one space of indent.
    private static func listItem(_ line: Substring) -> String? {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= maxIndent else { return nil }
        let rest = line.dropFirst(indent)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, let mark = rest.dropFirst(digits.count).first, mark == "." || mark == ")",
           rest.dropFirst(digits.count + 1).first == " " {
            return nonEmpty(rest.dropFirst(digits.count + 2))
        }
        for marker in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "] where rest.hasPrefix(marker) {
            return nonEmpty(rest.dropFirst(marker.count))
        }
        return nil
    }

    private static func nonEmpty(_ text: Substring) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Reads off the main actor, capped at `maxBytes`.
    /// Complexity: O(maxBytes) time, O(maxBytes) space
    @concurrent static func load(_ url: URL) async throws -> PlanDocument {
        let file = try await BoundedFile.readText(url, maxBytes: maxBytes)
        return parse(file.text, path: url, isTruncated: file.isTruncated)
    }
}

nonisolated protocol PlanLoading: Sendable {
    func load(_ url: URL) async throws -> PlanDocument
}

nonisolated struct FilePlanLoader: PlanLoading {
    func load(_ url: URL) async throws -> PlanDocument { try await PlanDocument.load(url) }
}
