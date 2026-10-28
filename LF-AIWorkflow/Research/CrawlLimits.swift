//
//  CrawlLimits.swift
//  LF-AIWorkflow
//

import Foundation

/// Hard caps for a crawl. UI values are passed through `clamped()` and can never exceed these.
nonisolated struct CrawlLimits: Sendable, Equatable {
    static let maxDepthCap = 2
    static let maxPagesCap = 50
    static let defaultMaxPages = 10

    var depth = 0
    var maxPages = CrawlLimits.defaultMaxPages
    var perPageTimeout: Duration = .seconds(20)
    var settle: Duration = .milliseconds(1500)
    var maxLinksPerPage = 200
    var maxQueue = 500
    var totalDeadline: Duration = .seconds(600)
    var maxRedirects = 5
    var sameSiteOnly = true

    /// Complexity: O(1) time, O(1) space.
    func clamped() -> CrawlLimits {
        var c = self
        c.depth = min(max(depth, 0), Self.maxDepthCap)
        c.maxPages = min(max(maxPages, 1), Self.maxPagesCap)
        c.perPageTimeout = min(max(perPageTimeout, .seconds(1)), .seconds(20))
        c.settle = min(max(settle, .zero), .milliseconds(1500))
        c.maxLinksPerPage = min(max(maxLinksPerPage, 0), 200)
        c.maxQueue = min(max(maxQueue, 1), 500)
        c.totalDeadline = min(max(totalDeadline, .seconds(1)), .seconds(600))
        c.maxRedirects = min(max(maxRedirects, 0), 5)
        c.sameSiteOnly = true
        return c
    }
}
