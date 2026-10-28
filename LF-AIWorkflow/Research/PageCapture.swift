//
//  PageCapture.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct SavedSource: Sendable, Equatable {
    let file: URL
    let tableFiles: [URL]
    let tokens: Int
    let looksEmpty: Bool
}

/// Turns a validated `CapturedPage` into `sources/NN-<slug>.md` and `tables/NN-<k>.csv`.
nonisolated enum PageCapture {
    /// Complexity: O(text + cells) time, O(text + cells) space
    static func save(_ page: CapturedPage, index: Int, store: ResearchStore, folder: ResearchFolder) async throws -> SavedSource {
        let file = try await store.writeSource(
            ResearchSource(url: page.url.absoluteString, title: page.title, body: page.text),
            index: index, in: folder)
        var tableFiles: [URL] = []
        for (k, rows) in page.tables.enumerated() {
            tableFiles.append(try await store.writeTable(rows, source: index, index: k + 1, in: folder))
        }
        return SavedSource(file: file, tableFiles: tableFiles, tokens: TokenEstimator.estimate(page.text),
                           looksEmpty: CapturedPage.looksEmpty(page))
    }
}
