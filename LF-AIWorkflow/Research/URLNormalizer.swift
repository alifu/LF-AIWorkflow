//
//  URLNormalizer.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum URLNormalizer {
    static let maxLength = 2048

    /// Canonical http(s) URL or nil. Idempotent.
    /// Complexity: O(n log n) time (query sort), O(n) space.
    static func normalize(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxLength,
              var c = URLComponents(string: trimmed),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              c.user == nil, c.password == nil,
              let host = c.host?.lowercased(), !host.isEmpty else { return nil }
        c.scheme = scheme
        c.host = host
        c.fragment = nil
        if (scheme == "http" && c.port == 80) || (scheme == "https" && c.port == 443) { c.port = nil }
        if c.path.isEmpty { c.path = "/" }
        if let items = c.queryItems {
            let kept = items.filter { !isTracking($0.name) }
                .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            c.queryItems = kept.isEmpty ? nil : kept
        }
        guard let url = c.url, url.absoluteString.utf8.count <= maxLength else { return nil }
        return url
    }

    /// Equal host after stripping one leading `www.`.
    /// Complexity: O(h) time, O(h) space.
    static func sameSite(_ a: URL, _ b: URL) -> Bool {
        guard let ha = siteHost(a), let hb = siteHost(b) else { return false }
        return ha == hb
    }

    private static func siteHost(_ u: URL) -> String? {
        guard var h = u.host(percentEncoded: true)?.lowercased() else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    private static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("utm_") || n.hasPrefix("mc_") || n == "gclid" || n == "fbclid"
    }
}
