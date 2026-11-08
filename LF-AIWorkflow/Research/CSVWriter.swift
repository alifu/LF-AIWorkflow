//
//  CSVWriter.swift
//  LF-AIWorkflow
//

import Foundation

/// RFC 4180 rows with a spreadsheet formula-injection guard.
nonisolated enum CSVWriter {
    private static let formulaLeaders: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    /// Complexity: O(total cell length) time, O(same) space
    static func row(_ cells: [String]) -> String {
        cells.map(cell).joined(separator: ",") + "\r\n"
    }

    /// Complexity: O(total cell length) time, O(same) space
    static func document(_ rows: [[String]]) -> String {
        rows.map(row).joined()
    }

    /// Complexity: O(n) time, O(n) space
    private static func cell(_ raw: String) -> String {
        let guarded = startsFormula(raw) ? "'" + raw : raw
        guard guarded.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return guarded }
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Spreadsheets skip leading whitespace and fold full-width forms (＝ ＋ － ＠) to ASCII, so both are
    /// normalized before the first-character check.
    /// Complexity: O(n) time, O(n) space
    private static func startsFormula(_ raw: String) -> Bool {
        if let first = raw.first, formulaLeaders.contains(first) { return true }
        let folded = raw.precomposedStringWithCompatibilityMapping
        guard let lead = folded.first(where: { !$0.isWhitespace }) else { return false }
        return formulaLeaders.contains(lead)
    }
}
