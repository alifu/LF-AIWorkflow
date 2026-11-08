//
//  SourcesPreview.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum SourceFlag: Sendable, Equatable, Hashable {
    case looksEmpty, duplicate, removed
}

nonisolated struct SourcesPreviewRow: Sendable, Equatable {
    /// 1-based position in the capture order; `send(_:excluded:)` uses these numbers.
    let index: Int
    let title: String
    let host: String
    let tokens: Int
    let tables: Int
    let flags: Set<SourceFlag>
}

/// What the user reviews before anything is sent to Claude.
nonisolated struct SourcesPreview: Sendable, Equatable {
    let rows: [SourcesPreviewRow]
    let removedLines: Int
    let totalTokens: Int

    /// `cleaned[i]` is `original[i]` after boilerplate removal; `duplicates` comes from `TextCleaner.duplicates`.
    /// Complexity: O(total text) time, O(n) space for n pages
    static func make(original: [CapturedPage], cleaned: [CapturedPage], removedLines: Int,
                     duplicates: [Int?]) -> SourcesPreview {
        let rows = cleaned.enumerated().map { i, page -> SourcesPreviewRow in
            var flags = Set<SourceFlag>()
            if CapturedPage.looksEmpty(page) { flags.insert(.looksEmpty) }
            if i < duplicates.count, duplicates[i] != nil { flags.insert(.duplicate) }
            if page.text.count < original[i].text.count { flags.insert(.removed) }
            return SourcesPreviewRow(index: i + 1, title: page.title, host: page.url.host ?? "",
                                     tokens: TokenEstimator.estimate(page.text), tables: page.tables.count, flags: flags)
        }
        return SourcesPreview(rows: rows, removedLines: removedLines, totalTokens: rows.reduce(0) { $0 + $1.tokens })
    }
}
