//
//  Crawler.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated protocol PageRendering: Sendable {
    func render(_ url: URL, settle: Duration, timeout: Duration) async throws -> CapturedPage
}

/// Bridges the main-actor `WebPageRenderer` to the nonisolated `PageRendering` protocol.
nonisolated struct WebPageRendering: PageRendering {
    let renderer: WebPageRenderer

    func render(_ url: URL, settle: Duration, timeout: Duration) async throws -> CapturedPage {
        try await renderer.render(url, settle: settle, timeout: timeout)
    }
}

nonisolated enum SkipReason: Sendable, Equatable {
    case invalidURL
    case blockedHost
    case blockedAddress
    case resolveFailed
    case crossSite
    case robots
    case blockedRedirect
    case renderFailed(String)
}

nonisolated enum CrawlStop: Sendable, Equatable { case completed, maxPages, deadline, cancelled }

nonisolated struct CrawlSummary: Sendable, Equatable {
    let fetched: Int
    let skipped: Int
    let stop: CrawlStop
}

nonisolated enum CrawlEvent: Sendable, Equatable {
    case fetched(CapturedPage, depth: Int)
    case skipped(URL, SkipReason)
    case finished(CrawlSummary)
}

/// Breadth-first, same-site crawler. Every URL (typed or discovered) passes the same gates.
actor Crawler {
    private struct Item { let url: URL; let depth: Int; let root: URL }

    private let renderer: any PageRendering
    private let robots: RobotsCache
    private let resolver: any HostResolving
    private let policy: HostPolicy
    private let limiter: HostRateLimiter

    init(renderer: any PageRendering, robots: RobotsCache, resolver: any HostResolving,
         policy: HostPolicy, limiter: HostRateLimiter) {
        self.renderer = renderer
        self.robots = robots
        self.resolver = resolver
        self.policy = policy
        self.limiter = limiter
    }

    /// Complexity: O(p * l) time and O(p * l) space for p pages and l links per page (both capped).
    nonisolated func crawl(start: [URL], limits: CrawlLimits) -> AsyncThrowingStream<CrawlEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let summary = try await self.run(start: start, limits: limits.clamped()) { continuation.yield($0) }
                    continuation.yield(.finished(summary))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.finished(CrawlSummary(fetched: 0, skipped: 0, stop: .cancelled)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(start: [URL], limits: CrawlLimits, emit: @Sendable (CrawlEvent) -> Void) async throws -> CrawlSummary {
        let deadline = ContinuousClock.now.advanced(by: limits.totalDeadline)
        var visited = Set<String>()
        var queue: [Item] = []
        var head = 0
        var fetched = 0
        var skipped = 0

        func skip(_ url: URL, _ reason: SkipReason) { skipped += 1; emit(.skipped(url, reason)) }

        for url in start {
            guard let n = URLNormalizer.normalize(url.absoluteString) else { skip(url, .invalidURL); continue }
            if visited.insert(n.absoluteString).inserted { queue.append(Item(url: n, depth: 0, root: n)) }
        }

        while head < queue.count {
            if Task.isCancelled { return CrawlSummary(fetched: fetched, skipped: skipped, stop: .cancelled) }
            if fetched >= limits.maxPages { return CrawlSummary(fetched: fetched, skipped: skipped, stop: .maxPages) }
            if ContinuousClock.now >= deadline { return CrawlSummary(fetched: fetched, skipped: skipped, stop: .deadline) }
            let item = queue[head]
            head += 1

            let outcome = try await fetch(item, limits: limits)
            switch outcome {
            case .skipped(let reason):
                skip(item.url, reason)
            case .page(let page):
                guard visited.insert(page.url.absoluteString).inserted || page.url == item.url else { continue }
                fetched += 1
                emit(.fetched(page, depth: item.depth))
                guard item.depth < limits.depth else { continue }
                for link in page.links.prefix(limits.maxLinksPerPage) where queue.count - head < limits.maxQueue {
                    guard visited.insert(link.absoluteString).inserted else { continue }
                    queue.append(Item(url: link, depth: item.depth + 1, root: item.root))
                }
            }
        }
        return CrawlSummary(fetched: fetched, skipped: skipped, stop: .completed)
    }

    private enum Outcome { case skipped(SkipReason), page(CapturedPage) }

    private func fetch(_ item: Item, limits: CrawlLimits) async throws -> Outcome {
        let url = item.url
        guard policy.check(url).isAllowed, let host = url.host(percentEncoded: true) else { return .skipped(.blockedHost) }
        do {
            let addresses = try await resolver.addresses(for: host)
            guard policy.check(addresses: addresses).isAllowed else { return .skipped(.blockedAddress) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .skipped(.resolveFailed)
        }
        if limits.sameSiteOnly, !URLNormalizer.sameSite(url, item.root) { return .skipped(.crossSite) }
        guard await robots.isAllowed(url) else { return .skipped(.robots) }
        try await limiter.acquire(host: host, extraDelay: await robots.delay(for: url))
        do {
            let page = try await renderer.render(url, settle: limits.settle, timeout: limits.perPageTimeout)
            guard policy.check(page.url).isAllowed else { return .skipped(.blockedRedirect) }
            if limits.sameSiteOnly, !URLNormalizer.sameSite(page.url, item.root) { return .skipped(.crossSite) }
            return .page(page)
        } catch is CancellationError {
            throw CancellationError()
        } catch CaptureError.blockedNavigation {
            return .skipped(.blockedRedirect)
        } catch {
            return .skipped(.renderFailed(String(describing: error)))
        }
    }
}
