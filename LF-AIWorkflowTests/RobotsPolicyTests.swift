//
//  RobotsPolicyTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

private func rules(_ fixture: String, agent: String = "LF-AIWorkflow") throws -> RobotsRules {
    let text = String(decoding: try loadFixture(fixture), as: UTF8.self)
    return RobotsRules.parse(text, userAgent: agent)
}

struct RobotsRulesTests {
    @Test func longestMatchWins() throws {
        let r = try rules("robots_basic.txt")
        #expect(!r.allows(path: "/private/x"))
        #expect(r.allows(path: "/private/public/x"))
        #expect(r.allows(path: "/other"))
    }

    @Test func wildcardAndEndAnchor() throws {
        let r = try rules("robots_basic.txt")
        #expect(!r.allows(path: "/a/b.pdf"))
        #expect(r.allows(path: "/a/b.pdf?x=1"))
        #expect(!r.allows(path: "/tmpfile"))
    }

    @Test func crawlDelayParsed() throws {
        #expect(try rules("robots_basic.txt").crawlDelay == .seconds(3))
        #expect(try rules("robots_empty_disallow.txt").crawlDelay == nil)
    }

    @Test func emptyDisallowAllowsAll() throws {
        let r = try rules("robots_empty_disallow.txt")
        #expect(r.allows(path: "/anything"))
    }

    @Test func specificAgentBeatsStar() throws {
        let r = try rules("robots_agent.txt")
        #expect(r.allows(path: "/docs/a"))
        #expect(!r.allows(path: "/docs/secret/x"))
        let other = try rules("robots_agent.txt", agent: "OtherBot")
        #expect(!other.allows(path: "/docs/a"))
    }

    @Test func tieGoesToAllow() {
        let r = RobotsRules.parse("User-agent: *\nDisallow: /a\nAllow: /a\n", userAgent: "LF-AIWorkflow")
        #expect(r.allows(path: "/a"))
    }

    @Test func malformedLinesIgnoredAndBOMStripped() throws {
        let r = try rules("robots_malformed.txt")
        #expect(!r.allows(path: "/ok"))
        #expect(r.allows(path: "/nocolon"))
        #expect(r.crawlDelay == nil)
    }

    @Test func percentEncodingNormalized() throws {
        let r = try rules("robots_malformed.txt")
        #expect(!r.allows(path: "/a~b"))
        #expect(!r.allows(path: "/a%7Eb"))
    }

    @Test func oversizedInputTruncated() {
        let filler = String(repeating: "# pad\n", count: 100_000)
        let r = RobotsRules.parse(filler + "User-agent: *\nDisallow: /late\n", userAgent: "LF-AIWorkflow")
        #expect(r.allows(path: "/late"))
    }

    @Test func noRulesAllowsAll() {
        #expect(RobotsRules.parse("", userAgent: "LF-AIWorkflow").allows(path: "/x"))
        #expect(RobotsRules.allowAll.allows(path: "/x"))
        #expect(!RobotsRules.disallowAll.allows(path: "/x"))
    }
}

private final class StubFetcher: RobotsFetching, Sendable {
    let result: Result<RobotsFetchResult, any Error>
    let counter = Counter()
    actor Counter { var n = 0; func bump() { n += 1 } }
    init(_ result: Result<RobotsFetchResult, any Error>) { self.result = result }
    func fetch(_ url: URL) async throws -> RobotsFetchResult {
        await counter.bump()
        return try result.get()
    }
}

struct RobotsCacheTests {
    private let url = URL(string: "https://example.com/page")!

    private func cache(_ r: Result<RobotsFetchResult, any Error>) -> (RobotsCache, StubFetcher) {
        let f = StubFetcher(r)
        return (RobotsCache(fetcher: f, policy: .standard), f)
    }

    @Test func okParsesBody() async {
        let (c, _) = cache(.success(.init(status: 200, body: "User-agent: *\nDisallow: /x\n")))
        #expect(await c.isAllowed(url) == true)
        #expect(await c.isAllowed(URL(string: "https://example.com/x")!) == false)
    }

    @Test func clientErrorAllowsAll() async {
        let (c, _) = cache(.success(.init(status: 404, body: "")))
        #expect(await c.isAllowed(url) == true)
    }

    @Test func serverErrorDisallowsAll() async {
        let (c, _) = cache(.success(.init(status: 503, body: "")))
        #expect(await c.isAllowed(url) == false)
    }

    @Test func networkErrorDisallowsAll() async {
        let (c, _) = cache(.failure(URLError(.timedOut)))
        #expect(await c.isAllowed(url) == false)
    }

    @Test func oneFetchPerHost() async {
        let (c, f) = cache(.success(.init(status: 200, body: "")))
        _ = await c.isAllowed(url)
        _ = await c.isAllowed(URL(string: "https://example.com/other")!)
        #expect(await f.counter.n == 1)
        _ = await c.isAllowed(URL(string: "http://example.com/other")!)
        #expect(await f.counter.n == 2)
    }

    @Test func blockedHostNeverFetched() async {
        let (c, f) = cache(.success(.init(status: 200, body: "")))
        #expect(await c.isAllowed(URL(string: "http://127.0.0.1/")!) == false)
        #expect(await f.counter.n == 0)
    }

    @Test func delayClampedBetweenOneAndTenSeconds() async {
        let (a, _) = cache(.success(.init(status: 200, body: "User-agent: *\nCrawl-delay: 0\n")))
        #expect(await a.delay(for: url) == .seconds(1))
        let (b, _) = cache(.success(.init(status: 200, body: "User-agent: *\nCrawl-delay: 99\n")))
        #expect(await b.delay(for: url) == .seconds(10))
        let (d, _) = cache(.success(.init(status: 200, body: "User-agent: *\nCrawl-delay: 4\n")))
        #expect(await d.delay(for: url) == .seconds(4))
    }
}
