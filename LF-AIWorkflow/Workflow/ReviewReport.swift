//
//  ReviewReport.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum Severity: Int, Sendable, Comparable, CaseIterable {
    case critical, high, medium, low, info

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Case-insensitive; accepts MED for medium.
    init?(label: String) {
        switch label.uppercased() {
        case "CRITICAL": self = .critical
        case "HIGH": self = .high
        case "MEDIUM", "MED": self = .medium
        case "LOW": self = .low
        case "INFO": self = .info
        default: return nil
        }
    }

    var label: String { String(describing: self).uppercased() }
}

nonisolated struct Finding: Sendable, Equatable {
    let severity: Severity
    let file: String
    let line: Int?
    let issue: String
    let suggestion: String?
}

nonisolated struct ReviewReport: Sendable, Equatable {
    let findings: [Finding]
    let unparsedLineCount: Int

    enum SaveError: Error, Equatable { case invalidSlug(String) }

    /// Parses lines shaped like `[sev] file:line - issue - suggestion`. A line that starts with a bracketed word
    /// but is not a valid finding counts as unparsed; other prose is ignored. Result is sorted by severity, file, line
    /// (stable for equal keys).
    /// Complexity: O(n + f log f) time, O(f) space
    static func parse(_ text: String) -> ReviewReport {
        var found: [Finding] = []
        var unparsed = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            switch parseLine(rawLine) {
            case .finding(let f): found.append(f)
            case .malformed: unparsed += 1
            case .prose: break
            }
        }
        return ReviewReport(findings: ordered(found), unparsedLineCount: unparsed)
    }

    /// Severity, then file, then line (no line last); equal keys keep their input order.
    /// Complexity: O(f log f) time, O(f) space
    static func ordered(_ findings: [Finding]) -> [Finding] {
        findings.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if a.severity != b.severity { return a.severity < b.severity }
            if a.file != b.file { return a.file < b.file }
            let (la, lb) = (a.line ?? Int.max, b.line ?? Int.max)
            if la != lb { return la < lb }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Complexity: O(f) time, O(f) space
    func markdown(title: String) -> String {
        var out = "# Review: \(title)\n\n"
        if findings.isEmpty { out += "No findings.\n" }
        for f in findings {
            let location = f.line.map { "\(f.file):\($0)" } ?? f.file
            out += "- **\(f.severity.label)** `\(location)` - \(f.issue)\n"
            if let suggestion = f.suggestion { out += "  - Suggestion: \(suggestion)\n" }
        }
        if unparsedLineCount > 0 { out += "\n_\(unparsedLineCount) line(s) could not be parsed._\n" }
        return out
    }

    /// Writes `.claude/reviews/<slug>.md` under `projectRoot` atomically. The slug must be a plain file name
    /// (letters, digits, `.`, `_`, `-`; no leading dot), so it cannot escape the reviews directory.
    /// Complexity: O(size) time, O(size) space
    func save(projectRoot: URL, slug: String) throws -> URL {
        guard Self.isSafeSlug(slug) else { throw SaveError.invalidSlug(slug) }
        let dir = projectRoot.appendingPathComponent(".claude/reviews", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(slug).md")
        try markdown(title: slug).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func isSafeSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, !slug.hasPrefix(".") else { return false }
        return slug.unicodeScalars.allSatisfy {
            ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
        }
    }

    private enum LineKind { case finding(Finding), malformed, prose }

    private static func parseLine(_ raw: Substring) -> LineKind {
        var rest = raw.drop(while: { $0 == " " || $0 == "\t" })
        rest = stripListMarker(rest)
        guard rest.first == "[", let close = rest.firstIndex(of: "]") else { return .prose }
        let label = rest[rest.index(after: rest.startIndex)..<close]
        guard !label.isEmpty, label.allSatisfy(\.isLetter) else { return .prose }
        guard let severity = Severity(label: String(label)) else { return .malformed }
        let body = rest[rest.index(after: close)...].drop(while: { $0 == " " })
        guard let (file, line, tail) = splitLocation(body), !file.isEmpty else { return .malformed }
        let (issue, suggestion) = splitIssue(tail)
        guard !issue.isEmpty else { return .malformed }
        return .finding(Finding(severity: severity, file: file, line: line, issue: issue, suggestion: suggestion))
    }

    private static func stripListMarker(_ s: Substring) -> Substring {
        if let first = s.first, first == "-" || first == "*", s.dropFirst().first == " " {
            return s.dropFirst().drop(while: { $0 == " " })
        }
        let digits = s.prefix(while: \.isNumber)
        if !digits.isEmpty {
            let after = s.dropFirst(digits.count)
            if let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " {
                return after.dropFirst().drop(while: { $0 == " " })
            }
        }
        return s
    }

    /// Returns file, optional line and the text after the location.
    private static func splitLocation(_ body: Substring) -> (String, Int?, Substring)? {
        var path: Substring
        var after: Substring
        if body.first == "`" {
            let inner = body.dropFirst()
            guard let end = inner.firstIndex(of: "`") else { return nil }
            path = inner[..<end]
            after = inner[inner.index(after: end)...]
            // `:line` may sit outside the backticks.
            if after.first == ":" {
                let digits = after.dropFirst().prefix(while: \.isNumber)
                if !digits.isEmpty {
                    return (String(path), Int(digits), after.dropFirst(1 + digits.count))
                }
            }
        } else {
            let (head, remainder) = splitAtSeparator(body)
            path = head
            after = remainder
        }
        if body.first != "`", let colon = path.lastIndex(of: ":") {
            let digits = path[path.index(after: colon)...]
            if !digits.isEmpty, digits.allSatisfy(\.isNumber), let n = Int(digits) {
                return (String(path[..<colon]), n, after)
            }
        }
        if body.first == "`", let colon = path.lastIndex(of: ":"),
           let n = Int(path[path.index(after: colon)...]) {
            return (String(path[..<colon]), n, after)
        }
        return (String(path).trimmingCharacters(in: .whitespaces), nil, after)
    }

    /// Splits at the first ` - ` or ` \u{2014} ` separator.
    private static func splitAtSeparator(_ s: Substring) -> (Substring, Substring) {
        var best: Range<Substring.Index>?
        for sep in [" - ", " \u{2014} "] {
            if let r = s.range(of: sep), best == nil || r.lowerBound < best!.lowerBound { best = r }
        }
        guard let r = best else { return (s, s[s.endIndex...]) }
        return (s[..<r.lowerBound], s[r.upperBound...])
    }

    private static func splitIssue(_ tail: Substring) -> (String, String?) {
        var text = tail.drop(while: { $0 == " " })
        for sep in ["- ", "\u{2014} "] where text.hasPrefix(sep) {
            text = text.dropFirst(sep.count)
            break
        }
        let (issue, suggestion) = splitAtSeparator(text)
        let sug = suggestion.trimmingCharacters(in: .whitespaces)
        return (issue.trimmingCharacters(in: .whitespaces), sug.isEmpty ? nil : sug)
    }
}
