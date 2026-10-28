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

    private static func cell(_ raw: String) -> String {
        let guarded = raw.first.map { formulaLeaders.contains($0) } == true ? "'" + raw : raw
        guard guarded.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return guarded }
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
