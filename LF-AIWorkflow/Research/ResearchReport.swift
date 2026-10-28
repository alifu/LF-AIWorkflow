//
//  ResearchReport.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct ComparisonTable: Sendable, Equatable {
    let header: [String]
    let rows: [[String]]

    /// Header plus rows, ready for `CSVWriter.document` (which applies the formula guard).
    /// Complexity: O(rows x cols) time, O(rows x cols) space
    var csvRows: [[String]] { [header] + rows }
}

/// Parsed, untrusted model answer.
nonisolated struct ResearchReport: Sendable, Equatable {
    let answer: String
    let table: ComparisonTable?
    let citations: [Int]
    let unknownCitations: [Int]
    let unsourcedCount: Int
}
