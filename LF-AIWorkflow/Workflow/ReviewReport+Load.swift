//
//  ReviewReport+Load.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated extension ReviewReport {
    static let maxLoadBytes = 256 * 1024
    static let maxLoadedFindings = 500

    /// Inverse of `markdown(title:)`; also accepts the `[sev] file:line - issue` form. Lines that look like findings but
    /// cannot be read count as unparsed; everything else is ignored.
    /// Complexity: O(n + f log f) time, O(f) space
    static func parseSaved(_ text: String) -> ReviewReport {
        var findings: [Finding] = []
        var unparsed = 0
        var lastWasFinding = false
        for raw in text.split(whereSeparator: \.isNewline) {
            guard findings.count < maxLoadedFindings else { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(suggestionPrefix) {
                if lastWasFinding, let last = findings.last {
                    findings[findings.count - 1] = Finding(severity: last.severity, file: last.file, line: last.line,
                                                           issue: last.issue, suggestion: String(line.dropFirst(suggestionPrefix.count)))
                }
                lastWasFinding = false
            } else if line.hasPrefix("- **") {
                if let finding = savedFinding(line) { findings.append(finding); lastWasFinding = true } else { unparsed += 1; lastWasFinding = false }
            } else if let count = unparsedFooterCount(line) {
                unparsed += count
                lastWasFinding = false
            } else {
                let parsed = ReviewReport.parse(line)
                findings += parsed.findings
                unparsed += parsed.unparsedLineCount
                lastWasFinding = false
            }
        }
        return ReviewReport(findings: ordered(findings), unparsedLineCount: unparsed)
    }

    private static let suggestionPrefix = "- Suggestion: "

    /// `- **HIGH** `file:line` - issue`
    private static func savedFinding(_ line: String) -> Finding? {
        let afterBullet = line.dropFirst("- **".count)
        guard let close = afterBullet.range(of: "**"), let severity = Severity(label: String(afterBullet[..<close.lowerBound])) else { return nil }
        let rest = afterBullet[close.upperBound...].drop(while: { $0 == " " })
        guard rest.first == "`", let end = rest.dropFirst().firstIndex(of: "`") else { return nil }
        let location = rest.dropFirst()[..<end]
        let tail = rest[rest.index(after: end)...]
        guard tail.hasPrefix(" - ") else { return nil }
        let issue = tail.dropFirst(3).trimmingCharacters(in: .whitespaces)
        var file = String(location)
        var lineNumber: Int?
        if let colon = location.lastIndex(of: ":"), let n = Int(location[location.index(after: colon)...]) {
            file = String(location[..<colon])
            lineNumber = n
        }
        guard !file.isEmpty, !issue.isEmpty else { return nil }
        return Finding(severity: severity, file: file, line: lineNumber, issue: issue, suggestion: nil)
    }

    /// `_2 line(s) could not be parsed._`
    private static func unparsedFooterCount(_ line: String) -> Int? {
        guard line.hasPrefix("_"), line.hasSuffix("line(s) could not be parsed._") else { return nil }
        return Int(line.dropFirst().prefix(while: \.isNumber))
    }

    /// Bounded read (256 KB, 500 findings) off the main actor.
    /// Complexity: O(size) time, O(size) space
    @concurrent static func load(markdownAt url: URL) async throws -> ReviewReport {
        let file = try await BoundedFile.readText(url, maxBytes: maxLoadBytes)
        return parseSaved(file.text)
    }
}

nonisolated protocol ReviewLoading: Sendable {
    func load(_ url: URL) async throws -> ReviewReport
}

nonisolated struct FileReviewLoader: ReviewLoading {
    func load(_ url: URL) async throws -> ReviewReport { try await ReviewReport.load(markdownAt: url) }
}
