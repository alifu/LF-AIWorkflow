//
//  RobotsPolicy.swift
//  LF-AIWorkflow
//

import Foundation

/// Parsed robots.txt rules for one user agent (RFC 9309).
nonisolated struct RobotsRules: Sendable, Equatable {
    struct Rule: Sendable, Equatable {
        let allow: Bool
        let pattern: [UInt8]
    }

    static let productToken = "LF-AIWorkflow"
    static let maxInputBytes = 500 * 1024
    static let allowAll = RobotsRules(rules: [], crawlDelay: nil)
    static let disallowAll = RobotsRules(rules: [Rule(allow: false, pattern: Array("/".utf8))], crawlDelay: nil)

    let rules: [Rule]
    let crawlDelay: Duration?

    /// Complexity: O(n) time, O(n) space for input size n (capped at 500 KiB).
    static func parse(_ text: String, userAgent: String = productToken) -> RobotsRules {
        let capped = Array(text.utf8.prefix(maxInputBytes))
        var content = String(decoding: capped, as: UTF8.self)
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        let agent = userAgent.lowercased()

        struct Group { var agents: [String] = []; var rules: [Rule] = []; var delay: Duration? }
        var groups: [Group] = []
        var current = Group()
        var collectingAgents = true

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "user-agent":
                if !collectingAgents {
                    groups.append(current)
                    current = Group()
                    collectingAgents = true
                }
                current.agents.append(value.lowercased())
            case "allow", "disallow":
                collectingAgents = false
                guard !value.isEmpty else { continue }
                current.rules.append(Rule(allow: key == "allow", pattern: normalized(value)))
            case "crawl-delay":
                collectingAgents = false
                if let seconds = Double(value), seconds >= 0, seconds.isFinite {
                    current.delay = .milliseconds(Int((seconds * 1000).rounded()))
                }
            default:
                continue
            }
        }
        groups.append(current)

        let specific = groups.filter { g in g.agents.contains { !$0.isEmpty && $0 != "*" && agent.contains($0) } }
        let chosen = specific.isEmpty ? groups.filter { $0.agents.contains("*") } : specific
        return RobotsRules(rules: chosen.flatMap(\.rules), crawlDelay: chosen.compactMap(\.delay).first)
    }

    /// Longest matching pattern wins; a tie goes to Allow.
    /// Complexity: O(r * p) time for r rules of pattern length p, O(p) space.
    func allows(path: String) -> Bool {
        let target = Self.normalized(path.isEmpty ? "/" : path)
        var best: (length: Int, allow: Bool)?
        for rule in rules where Self.matches(rule.pattern, target) {
            let length = rule.pattern.count
            if let b = best, b.length > length || (b.length == length && b.allow) { continue }
            best = (length, rule.allow)
        }
        return best?.allow ?? true
    }

    // MARK: - Matching

    /// Percent-encoding normalization: unreserved escapes decoded, remaining hex upper-cased.
    private static func normalized(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x25, i + 2 < bytes.count + 0, let hi = hex(bytes[i + 1]), let lo = hex(bytes[i + 2]) {
                let v = UInt8(hi << 4 | lo)
                if isUnreserved(v) {
                    out.append(v)
                } else {
                    out.append(contentsOf: [0x25, upperHex(hi), upperHex(lo)])
                }
                i += 3
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return out
    }

    private static func hex(_ b: UInt8) -> Int? {
        switch b {
        case 0x30...0x39: return Int(b) - 0x30
        case 0x41...0x46: return Int(b) - 0x41 + 10
        case 0x61...0x66: return Int(b) - 0x61 + 10
        default: return nil
        }
    }

    private static func upperHex(_ v: Int) -> UInt8 {
        UInt8(v < 10 ? 0x30 + v : 0x41 + v - 10)
    }

    private static func isUnreserved(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
    }

    /// Prefix match with `*` wildcards and optional trailing `$` anchor, no recursion.
    private static func matches(_ pattern: [UInt8], _ text: [UInt8]) -> Bool {
        var pat = pattern
        var anchored = false
        if pat.last == 0x24 { anchored = true; pat.removeLast() }
        let segments = pat.split(separator: 0x2A, omittingEmptySubsequences: false).map(Array.init)
        guard let first = segments.first else { return true }
        guard text.starts(with: first) else { return false }
        var pos = first.count
        if segments.count == 1 { return !anchored || pos == text.count }
        for seg in segments[1..<(segments.count - 1)] {
            guard let at = find(seg, in: text, from: pos) else { return false }
            pos = at + seg.count
        }
        let last = segments[segments.count - 1]
        if anchored {
            return text.count - last.count >= pos && text.suffix(last.count).elementsEqual(last)
        }
        return find(last, in: text, from: pos) != nil
    }

    private static func find(_ needle: [UInt8], in text: [UInt8], from: Int) -> Int? {
        if needle.isEmpty { return from <= text.count ? from : nil }
        guard text.count - from >= needle.count else { return nil }
        for start in from...(text.count - needle.count) where text[start] == needle[0] {
            if text[start..<(start + needle.count)].elementsEqual(needle) { return start }
        }
        return nil
    }
}
