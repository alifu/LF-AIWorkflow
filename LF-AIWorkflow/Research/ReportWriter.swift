//
//  ReportWriter.swift
//  LF-AIWorkflow
//

import Foundation

/// Parses and renders model output. Model output is untrusted: it is sanitized before it is stored or shown.
nonisolated enum ReportWriter {
    static let maxAnswerBytes = 1_000_000
    static let maxTableRows = 200
    static let maxTableCols = 30
    static let truncationNote = "\n\n_[Answer truncated: it exceeded the size limit.]_\n"

    /// Complexity: O(n) time, O(n) space (n = answer length, bounded by `maxAnswerBytes`)
    static func parse(_ text: String, sourceCount: Int) -> ResearchReport {
        let answer = sanitize(truncate(text))
        let lines = answer.components(separatedBy: "\n")
        let cited = citationNumbers(in: answer)
        let valid = Set(cited.filter { (1...max(sourceCount, 0)).contains($0) })
        return ResearchReport(
            answer: answer,
            table: firstTable(lines),
            citations: valid.sorted(),
            unknownCitations: Set(cited).subtracting(valid).sorted(),
            unsourcedCount: unsourced(lines)
        )
    }

    /// Answer plus an app-generated Sources list (the answer's own URL list is not trusted).
    /// Complexity: O(n + sources) time, O(n + sources) space
    static func render(_ report: ResearchReport, sources: [ResearchSource]) -> String {
        var out = report.answer.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n## Sources\n\n"
        for (i, s) in sources.enumerated() {
            let title = escapeInline(sanitizeLine(s.title))
            let url = sanitizeLine(s.url)
            out += "\(i + 1). \(title): <\(isHTTP(url) ? url : "invalid-url")>\n"
        }
        return out
    }

    /// Removes control characters, images, and non-http(s) links.
    /// Complexity: O(n) time, O(n) space
    static func sanitize(_ text: String) -> String {
        var s = String(String.UnicodeScalarView(text.unicodeScalars.filter(isAllowed)))
        s = replace(imagePattern, in: s) { $0[1] }
        s = replace(linkPattern, in: s) { isHTTP($0[2]) ? "[\($0[1])](\($0[2]))" : $0[1] }
        s = replace(autolinkPattern, in: s) { isHTTP($0[1]) ? "<\($0[1])>" : "" }
        s = replace(refDefPattern, in: s) { isHTTP($0[2]) ? $0[0] : "" }
        return s
    }

    // MARK: - private

    private static let imagePattern = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]*\)"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\(\s*<?([^)>\s]*)[^)]*\)"#)
    private static let autolinkPattern = try! NSRegularExpression(pattern: #"<([A-Za-z][A-Za-z0-9+.\-]*:[^>\s]*)>"#)
    private static let refDefPattern = try! NSRegularExpression(pattern: #"(?m)^[ ]{0,3}\[([^\]]+)\]:[ ]*<?(\S+?)>?(?:[ ].*)?$"#)
    private static let citationPattern = try! NSRegularExpression(pattern: #"\[(\d{1,6})\]"#)

    private static func isAllowed(_ u: Unicode.Scalar) -> Bool {
        if u == "\n" || u == "\t" { return true }
        switch u.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return false
        default: return true
        }
    }

    private static func sanitizeLine(_ s: String) -> String {
        sanitize(s).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
    }

    private static func escapeInline(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\`*_[]<>".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    private static func isHTTP(_ s: String) -> Bool {
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func truncate(_ text: String) -> String {
        guard text.utf8.count > maxAnswerBytes else { return text }
        var cut = String(decoding: Array(text.utf8.prefix(maxAnswerBytes)), as: UTF8.self)
        cut.removeAll { $0 == "\u{FFFD}" }
        return cut + truncationNote
    }

    private static func replace(_ re: NSRegularExpression, in s: String, _ transform: ([String]) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += transform(groups)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func citationNumbers(in s: String) -> [Int] {
        let ns = s as NSString
        return citationPattern.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
    }

    private static func isTableRow(_ l: String) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.hasSuffix("|") && t.count > 1
    }

    private static func isSeparator(_ l: String) -> Bool {
        isTableRow(l) && cells(l).allSatisfy { !$0.isEmpty && $0.allSatisfy { ":-".contains($0) } }
    }

    private static func cells(_ l: String) -> [String] {
        var t = l.trimmingCharacters(in: .whitespaces)
        t.removeFirst()
        t.removeLast()
        return t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func firstTable(_ lines: [String]) -> ComparisonTable? {
        guard let start = lines.indices.dropLast().first(where: { isTableRow(lines[$0]) && isSeparator(lines[$0 + 1]) })
        else { return nil }
        let header = Array(cells(lines[start]).prefix(maxTableCols))
        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count, isTableRow(lines[i]), rows.count < maxTableRows {
            rows.append(Array(cells(lines[i]).prefix(maxTableCols)))
            i += 1
        }
        return ComparisonTable(header: header, rows: rows)
    }

    private static func unsourced(_ lines: [String]) -> Int {
        lines.filter { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#") && !isTableRow(t) && citationNumbers(in: t).isEmpty
        }.count
    }
}

/// Renders untrusted markdown, keeping only http(s) links.
nonisolated enum SafeMarkdown {
    /// Complexity: O(n) time, O(n) space
    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: ReportWriter.sanitize(markdown), options: options))
            ?? AttributedString(markdown)
        for run in a.runs {
            guard let url = run.link else { continue }
            let scheme = url.scheme?.lowercased()
            if scheme != "http" && scheme != "https" { a[run.range].link = nil }
        }
        return a
    }
}
