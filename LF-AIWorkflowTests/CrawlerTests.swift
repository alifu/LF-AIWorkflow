//
//  CrawlerTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private let longText = String(repeating: "word ", count: 80)

private func page(_ url: String, links: [String] = []) -> CapturedPage {
    CapturedPage(title: "T", url: URL(string: url)!, text: longText, headings: [], links: links.compactMap { URLNormalizer.normalize($0) },
                 tables: [], hasPasswordField: false)
}

/// Serves pages from a site map; a `redirects` entry reports a different final URL.
private final class FakeRenderer: PageRendering {
    private let site: [String: [String]]
    private let redirects: [String: String]
    private let log = Locked<[String]>([])
    init(site: [String: [String]], redirects: [String: String] = [:]) { self.site = site; self.redirects = redirects }
    var rendered: [String] { log.value }

    func render(_ url: URL, settle: Duration, timeout: Duration) async throws -> CapturedPage {
        log.mutate { $0.append(url.absoluteString) }
        let key = url.absoluteString
        if let final = redirects[key] { return page(final) }
        guard let links = site[key] else { throw CaptureError.renderFailed("404") }
        return page(key, links: links)
    }
}

private final class Locked<T: Sendable>: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var stored: T
    init(_ v: T) { stored = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&stored); lock.unlock() }
}

private struct FakeResolver: HostResolving {
    var map: [String: [IPAddress]] = [:]
    func addresses(for host: String) async throws -> [IPAddress] { map[host] ?? [.v4(0x5DB8D822)] }
}

private struct FakeRobotsFetcher: RobotsFetching {
    var body: String = ""
    var status = 404
    func fetch(_ url: URL) async throws -> RobotsFetchResult { RobotsFetchResult(status: status, body: body) }
}

private func makeCrawler(_ renderer: FakeRenderer, robots: FakeRobotsFetcher = FakeRobotsFetcher(), resolver: FakeResolver = FakeResolver(),
                         clock: ManualClock? = nil) -> Crawler {
    let clk = clock ?? ManualClock()
    return Crawler(renderer: renderer, robots: RobotsCache(fetcher: robots, policy: .standard), resolver: resolver,
                   policy: .standard, limiter: HostRateLimiter(clock: clk))
}

/// Collects events; advances the manual clock whenever the crawler sleeps for rate limiting.
private func collect(_ crawler: Crawler, start: [String], limits: CrawlLimits, clock: ManualClock? = nil) async throws -> [CrawlEvent] {
    let stream = crawler.crawl(start: start.map { URL(string: $0)! }, limits: limits)
    let pump = Task {
        guard let clock else { return }
        while !Task.isCancelled {
            await clock.waitForSleepers()
            clock.advance(by: .seconds(1))
        }
    }
    defer { pump.cancel() }
    var out: [CrawlEvent] = []
    for try await e in stream { out.append(e) }
    return out
}

private func fetchedURLs(_ events: [CrawlEvent]) -> [String] {
    events.compactMap { if case .fetched(let p, _) = $0 { p.url.absoluteString } else { nil } }
}

private func skips(_ events: [CrawlEvent]) -> [SkipReason] {
    events.compactMap { if case .skipped(_, let r) = $0 { r } else { nil } }
}

private func summary(_ events: [CrawlEvent]) -> CrawlSummary? {
    for case .finished(let s) in events { return s }
    return nil
}

struct CrawlerTests {
    @Test func limitsClampToHardCaps() {
        let c = CrawlLimits(depth: 9, maxPages: 500, perPageTimeout: .seconds(300), settle: .seconds(30)).clamped()
        #expect(c.depth == 2 && c.maxPages == 50 && c.perPageTimeout == .seconds(20) && c.settle == .milliseconds(1500))
        #expect(CrawlLimits().depth == 0 && CrawlLimits().maxPages == 10)
        #expect(CrawlLimits(depth: -1, maxPages: 0).clamped().maxPages == 1)
    }

    @Test func bfsOrderAndDepthCut() async throws {
        let r = FakeRenderer(site: [
            "https://a.example.com/": ["https://a.example.com/b", "https://a.example.com/c"],
            "https://a.example.com/b": ["https://a.example.com/d"],
            "https://a.example.com/c": [],
            "https://a.example.com/d": ["https://a.example.com/e"],
        ])
        let clock = ManualClock()
        let events = try await collect(makeCrawler(r, clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(depth: 1), clock: clock)
        #expect(fetchedURLs(events) == ["https://a.example.com/", "https://a.example.com/b", "https://a.example.com/c"])
        let deep = try await collect(makeCrawler(r, clock: clock), start: ["https://a.example.com/"],
                                     limits: CrawlLimits(depth: 2), clock: clock)
        #expect(fetchedURLs(deep).count == 4)
    }

    @Test func maxPagesCappedAtFiftyEvenIfAskedFiveHundred() async throws {
        var site: [String: [String]] = [:]
        let links = (0..<150).map { "https://a.example.com/p\($0)" }
        site["https://a.example.com/"] = links
        for l in links { site[l] = [] }
        let clock = ManualClock()
        let events = try await collect(makeCrawler(FakeRenderer(site: site), clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(depth: 1, maxPages: 500), clock: clock)
        #expect(fetchedURLs(events).count == 50)
        #expect(summary(events)?.stop == .maxPages)
    }

    @Test func crossSiteAndDuplicatesAreHandled() async throws {
        let r = FakeRenderer(site: [
            "https://a.example.com/": ["https://other.example.org/x", "https://a.example.com/p#frag",
                                       "https://a.example.com/p?utm_source=x", "https://a.example.com/p"],
            "https://a.example.com/p": [],
        ])
        let clock = ManualClock()
        let events = try await collect(makeCrawler(r, clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(depth: 1), clock: clock)
        #expect(fetchedURLs(events) == ["https://a.example.com/", "https://a.example.com/p"])
        #expect(skips(events) == [.crossSite])
        #expect(r.rendered.filter { $0.hasSuffix("/p") }.count == 1)
    }

    @Test func robotsDisallowedIsSkippedWithReason() async throws {
        let r = FakeRenderer(site: ["https://a.example.com/": ["https://a.example.com/private/x"],
                                    "https://a.example.com/private/x": []])
        let clock = ManualClock()
        let robots = FakeRobotsFetcher(body: "User-agent: *\nDisallow: /private/\n", status: 200)
        let events = try await collect(makeCrawler(r, robots: robots, clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(depth: 1), clock: clock)
        #expect(skips(events) == [.robots])
        #expect(!r.rendered.contains("https://a.example.com/private/x"))
    }

    @Test func redirectToLoopbackIsSkipped() async throws {
        let r = FakeRenderer(site: [:], redirects: ["https://a.example.com/": "http://127.0.0.1/admin"])
        let clock = ManualClock()
        let events = try await collect(makeCrawler(r, clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(), clock: clock)
        #expect(fetchedURLs(events).isEmpty)
        #expect(skips(events) == [.blockedRedirect])
    }

    @Test func resolverReturningPrivateAddressIsSkipped() async throws {
        let r = FakeRenderer(site: ["https://a.example.com/": []])
        let resolver = FakeResolver(map: ["a.example.com": [.v4(0x0A000005)]])
        let clock = ManualClock()
        let events = try await collect(makeCrawler(r, resolver: resolver, clock: clock), start: ["https://a.example.com/"],
                                       limits: CrawlLimits(), clock: clock)
        #expect(skips(events) == [.blockedAddress])
        #expect(r.rendered.isEmpty)
    }

    @Test func startURLsPassSameChecks() async throws {
        let r = FakeRenderer(site: [:])
        let clock = ManualClock()
        let events = try await collect(makeCrawler(r, clock: clock), start: ["http://127.0.0.1/", "http://localhost/", "ftp://x.com/"],
                                       limits: CrawlLimits(), clock: clock)
        #expect(r.rendered.isEmpty)
        #expect(skips(events).count == 3)
    }

    @Test func samehostRequestsAreSpacedButHostsAreNot() async throws {
        let clock = ManualClock()
        let limiter = HostRateLimiter(clock: clock)
        try await limiter.acquire(host: "a.com")
        try await limiter.acquire(host: "b.com")          // different host: immediate
        let second = Task { try await limiter.acquire(host: "a.com") }
        await clock.waitForSleepers()
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(999))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        try await second.value
        // crawl-delay larger than the minimum is honored
        let third = Task { try await limiter.acquire(host: "a.com", extraDelay: .seconds(5)) }
        await clock.waitForSleepers()
        clock.advance(by: .seconds(1))
        try await third.value
        let fourth = Task { try await limiter.acquire(host: "a.com") }
        await clock.waitForSleepers()
        clock.advance(by: .seconds(5))
        try await fourth.value
    }

    @Test func cancelStopsPromptly() async throws {
        let r = FakeRenderer(site: ["https://a.example.com/": ["https://a.example.com/b"], "https://a.example.com/b": []])
        let clock = ManualClock()
        let stream = makeCrawler(r, clock: clock).crawl(start: [URL(string: "https://a.example.com/")!], limits: CrawlLimits(depth: 1))
        let task = Task { () -> Int in
            var n = 0
            for try await e in stream { if case .fetched = e { n += 1 } }
            return n
        }
        await clock.waitForSleepers()      // second page waits on the 1 s spacing
        task.cancel()
        let n = try await task.value
        #expect(n == 1)
        #expect(r.rendered.count == 1)
    }
}
