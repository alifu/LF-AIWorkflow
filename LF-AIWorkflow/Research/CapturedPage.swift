//
//  CapturedPage.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum CaptureError: Error, Equatable, Sendable {
    case malformed
    case tooLarge
    case scriptMissing
    case renderFailed(String)
    case timedOut
    case blockedNavigation
}

/// Page data produced by `extract.js`. Page output is untrusted: every field is validated again here.
nonisolated struct CapturedPage: Sendable, Equatable {
    static let maxJSONBytes = 2 * 1024 * 1024
    static let maxText = 200_000
    static let maxHeadings = 200
    static let maxLinks = 300
    static let maxTables = 50
    static let maxRows = 500
    static let maxCols = 30
    static let maxCell = 500
    static let minUsefulChars = 200

    let title: String
    let url: URL
    let text: String
    let headings: [String]
    let links: [URL]
    let tables: [[[String]]]
    let hasPasswordField: Bool

    private struct Raw: Decodable {
        let v: Int
        let title: String
        let url: String
        let text: String
        let headings: [String]
        let links: [String]
        let tables: [[[String]]]
        let hasPasswordField: Bool?
    }

    /// Complexity: O(n) time, O(n) space (n = JSON size, bounded by `maxJSONBytes`)
    static func parse(_ json: String, policy: HostPolicy = .standard) throws -> CapturedPage {
        let data = Data(json.utf8)
        guard data.count <= maxJSONBytes else { throw CaptureError.tooLarge }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), raw.v == 1 else { throw CaptureError.malformed }
        guard let url = URLNormalizer.normalize(raw.url), policy.check(url) == .allowed else {
            throw CaptureError.malformed
        }
        guard raw.text.count <= maxText, raw.headings.count <= maxHeadings, raw.links.count <= maxLinks,
              raw.tables.count <= maxTables,
              raw.headings.allSatisfy({ $0.count <= maxCell }),
              raw.tables.allSatisfy({ t in
                  t.count <= maxRows && t.allSatisfy { $0.count <= maxCols && $0.allSatisfy { $0.count <= maxCell } }
              }) else { throw CaptureError.tooLarge }
        let links = raw.links.compactMap { URLNormalizer.normalize($0) }
        return CapturedPage(title: raw.title, url: url, text: raw.text, headings: raw.headings, links: links,
                            tables: raw.tables, hasPasswordField: raw.hasPasswordField ?? false)
    }

    /// Complexity: O(1) time, O(1) space
    static func looksEmpty(_ page: CapturedPage) -> Bool {
        page.hasPasswordField || page.text.count < minUsefulChars
    }
}
