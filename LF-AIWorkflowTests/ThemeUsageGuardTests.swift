//
//  ThemeUsageGuardTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing

/// Views must read colors, fonts, radii and shadows from `AppTheme` tokens, and never name a style.
/// `ThemeUsageGuard.allowlist` is the shrinking worklist of files that still use literals (file -> offending line count).
/// A file may never exceed its allowance; when it drops below, lower the entry (the test says so), so the list only
/// ever shrinks. Steps 7 and 8 of Phase 6 end with it empty.
struct ThemeUsageGuardTests {
    @Test func noNewLiteralVisualsOrStyleNames() throws {
        let report = try ThemeUsageGuard.scan()
        var problems: [String] = []
        for (file, lines) in report.sorted(by: { $0.key < $1.key }) {
            let allowed = ThemeUsageGuard.allowlist[file] ?? 0
            if lines.count > allowed {
                problems.append("\(file): \(lines.count) offending lines, allowed \(allowed)\n  " + lines.joined(separator: "\n  "))
            }
        }
        #expect(problems.isEmpty, "New hard-coded visuals; use theme tokens:\n\(problems.joined(separator: "\n"))")
    }

    @Test func allowlistHasNoStaleEntries() throws {
        let report = try ThemeUsageGuard.scan()
        let stale = ThemeUsageGuard.allowlist.filter { (report[$0.key]?.count ?? 0) < $0.value }
            .map { "\($0.key): allowed \($0.value), now \(report[$0.key]?.count ?? 0); lower the entry" }
        #expect(stale.isEmpty, "Allowlist must shrink with the code:\n\(stale.sorted().joined(separator: "\n"))")
    }

    @Test func scannerFlagsLiteralsAndIgnoresPreviewsAndComments() {
        let source = """
        // .foregroundStyle(.red) in a comment
        Text("x").font(.system(size: 9)).foregroundStyle(.secondary)
        Text("y").foregroundStyle(theme.palette(for: scheme).primaryText.color)
        RoundedRectangle(cornerRadius: 10).shadow(radius: 2)
        let s = ArtStyle.popArt
        #Preview {
            Color.red.font(.system(size: 1))
        }
        Color.orange
        """
        let hits = ThemeUsageGuard.offendingLines(in: source)
        #expect(hits.map(\.number) == [2, 4, 5, 9])
    }

    @Test func everyPatternHasAFixtureItDetects() {
        for (name, _) in ThemeUsageGuard.patterns {
            guard let fixture = ThemeUsageGuard.fixtures[name] else {
                Issue.record("pattern \(name) has no fixture")
                continue
            }
            #expect(ThemeUsageGuard.matchingPatterns(in: fixture).contains(name), "\(name) does not flag: \(fixture)")
            #expect(!ThemeUsageGuard.offendingLines(in: fixture).isEmpty, "\(name) fixture not reported")
        }
        #expect(Set(ThemeUsageGuard.fixtures.keys) == Set(ThemeUsageGuard.patterns.map(\.name)))
    }

    @Test func commentStripKeepsSlashesInsideStringsAndCutsRealComments() {
        #expect(ThemeUsageGuard.offendingLines(in: "let u = \"https://x.y/z\"; Color.red").count == 1)
        #expect(ThemeUsageGuard.offendingLines(in: "let u = URL(string: \"https://x.y\") // Color.red").isEmpty)
        #expect(ThemeUsageGuard.offendingLines(in: "let a = 1//Color.red").isEmpty)
        #expect(ThemeUsageGuard.offendingLines(in: "Text(\"a // b\").foregroundStyle(.red)").count == 1)
    }

    @Test func scanFindsTheSourceTree() throws {
        let report = try ThemeUsageGuard.scan()
        #expect(try ThemeUsageGuard.scanFileCount() > 20)
        #expect(!report.keys.contains { $0.hasPrefix("UI/Theme/") })
    }
}

enum ThemeUsageGuard {
    /// file (relative to the app target folder) -> allowed offending line count. Empty since Phase 6 step 8: no view uses literals.
    static let allowlist: [String: Int] = [:]

    private static let colorNames = "white|black|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray|secondary|primary|clear|accentColor"
    private static let materialNames = "ultraThin|thin|regular|thick|ultraThick|bar"

    /// Named so each pattern can be proven against its own fixture (`fixtures`).
    static let patterns: [(name: String, regex: NSRegularExpression)] = [
        ("styleName", #"\b(classic|popArt|PopArt|ClassicTheme|PopArtTheme|ArtStyle)\b"#),
        ("dotColor", #"(?<![A-Za-z0-9_])\.(\#(colorNames))\b"#),
        ("Color.name", #"\bColor\.(\#(colorNames))\b"#),
        ("Color(", #"\bColor\("#),
        ("NSColor", #"\bNSColor\b"#),
        ("UIColor", #"\bUIColor\b"#),
        ("NSFont", #"\bNSFont\b"#),
        ("foregroundColor", #"\.foregroundColor\("#),
        ("dotFont", #"\.font\(\.(system|caption2?|footnote|body|headline|subheadline|title[23]?|largeTitle|callout)\b"#),
        ("Font.system", #"\bFont\.system\("#),
        ("customFont", #"\bFont\.custom\(|\.font\(\.custom\("#),
        ("shadow", #"\.shadow\("#),
        ("cornerRadiusLabel", #"cornerRadius:\s*[0-9]"#),
        ("cornerRadiusModifier", #"\.cornerRadius\("#),
        ("opacityFraction", #"\.opacity\(\s*0?\.[0-9]"#),
        ("opacityZeroOne", #"\.opacity\(\s*[01]\s*\)"#),
        ("opacityDecimal", #"\.opacity\(\s*[0-9]+\.[0-9]+\s*\)"#),
        ("material", #"\.(\#(materialNames))Material\b|\bMaterial\.(\#(materialNames))\b"#),
        ("hexString", ##""#[0-9A-Fa-f]{3,8}"|\b0x[0-9A-Fa-f]{6,8}\b"##),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    /// One line per pattern that the pattern must flag; proves a pattern cannot be silently loosened.
    static let fixtures: [String: String] = [
        "styleName": "if theme.id == .popArt {",
        "dotColor": "Text(\"x\").foregroundStyle(.red)",
        "Color.name": "let c = Color.orange",
        "Color(": "let c = Color(red: 1, green: 0, blue: 0)",
        "NSColor": "let c = NSColor.systemRed",
        "UIColor": "let c = UIColor.red",
        "NSFont": "let f = NSFont.systemFont(ofSize: 9)",
        "foregroundColor": "Text(\"x\").foregroundColor(theme.x)",
        "dotFont": "Text(\"x\").font(.caption)",
        "Font.system": "let f = Font.system(size: 9)",
        "customFont": "Text(\"x\").font(.custom(\"Avenir\", size: 9))",
        "shadow": "view.shadow(radius: 2)",
        "cornerRadiusLabel": "RoundedRectangle(cornerRadius: 10)",
        "cornerRadiusModifier": "view.cornerRadius(8)",
        "opacityFraction": "view.opacity(0.5)",
        "opacityZeroOne": "view.opacity(1)",
        "opacityDecimal": "view.opacity(1.0)",
        "material": "view.background(.ultraThinMaterial)",
        "hexString": "let c = Color(hex: \"#FF8800\")",
    ]

    struct Hit { let number: Int; let text: String }

    /// Lines with a literal visual, ignoring `//` comments and `#Preview { ... }` blocks.
    /// Complexity: O(n * p) time, O(n) space (n = characters, p = patterns)
    static func offendingLines(in source: String) -> [Hit] {
        var hits: [Hit] = []
        var previewDepth = 0
        var inPreview = false
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inPreview, trimmed.hasPrefix("#Preview") { inPreview = true; previewDepth = 0 }
            if inPreview {
                previewDepth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if previewDepth <= 0 { inPreview = false }
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            let code = strippingLineComment(line)
            if !matchingPatterns(in: code).isEmpty {
                hits.append(Hit(number: index + 1, text: trimmed))
            }
        }
        return hits
    }

    /// Names of the patterns that match `code`.
    /// Complexity: O(c * p) time, O(p) space (c = characters, p = patterns)
    static func matchingPatterns(in code: String) -> [String] {
        let range = NSRange(code.startIndex..., in: code)
        return patterns.filter { $0.regex.firstMatch(in: code, range: range) != nil }.map(\.name)
    }

    /// Cuts a trailing `//` comment but keeps `//` inside string literals (URLs).
    /// Complexity: O(n) time, O(n) space
    static func strippingLineComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "/", previous == "/" {
                return String(line[..<line.index(before: index)])
            }
            previous = character
        }
        return line
    }

    /// Number of source files the scan covers.
    static func scanFileCount() throws -> Int { try sourceFiles().count }

    /// The test target copies `UI/` and `Notch/` sources into its bundle (build phase "Copy sources for theme guard"),
    /// because a test host reading the repository under ~/Documents blocks on a privacy prompt.
    static func sourceFiles() throws -> [(relative: String, url: URL)] {
        guard let root = Bundle(for: BundleToken.self).resourceURL?.appendingPathComponent("ThemeGuardSources") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var files: [(String, URL)] = []
        for folder in ["UI", "Notch"] {
            let base = root.appendingPathComponent(folder).resolvingSymlinksInPath()
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = folder + String(url.resolvingSymlinksInPath().path.dropFirst(base.path.count))
                if relative.hasPrefix("UI/Theme/") || url.lastPathComponent == "PreviewFixtures.swift" { continue }
                files.append((relative, url))
            }
        }
        return files
    }

    private final class BundleToken {}

    /// Palette token names (`palette.<name>`) that views pass to `foregroundStyle` or `foregroundColor`.
    /// Complexity: O(total source size) time, O(tokens) space
    static func paletteTextTokens() throws -> Set<String> {
        let token = try NSRegularExpression(pattern: #"palette\.([A-Za-z]+)"#)
        var found = Set<String>()
        for (_, url) in try sourceFiles() {
            for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            where line.contains("foregroundStyle(") || line.contains("foregroundColor(") {
                let range = NSRange(line.startIndex..., in: line)
                for match in token.matches(in: line, range: range) {
                    if let name = Range(match.range(at: 1), in: line) { found.insert(String(line[name])) }
                }
            }
        }
        return found
    }

    /// Offending lines per file under `UI/` and `Notch/`, skipping `UI/Theme/` and `PreviewFixtures.swift`.
    /// Complexity: O(total source size) time, O(offenders) space
    static func scan() throws -> [String: [String]] {
        var report: [String: [String]] = [:]
        for (relative, url) in try sourceFiles() {
            let hits = offendingLines(in: try String(contentsOf: url, encoding: .utf8))
            if !hits.isEmpty { report[relative] = hits.map { "\($0.number): \($0.text)" } }
        }
        return report
    }
}
