//
//  CrawlerIntegrationTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private func html(_ title: String, links: [String]) -> String {
    let body = String(repeating: "This sentence is real article content for the crawler integration test. ", count: 6)
    let anchors = links.map { "<a href=\"\($0)\">link</a>" }.joined()
    return "<!doctype html><html><head><title>\(title)</title></head><body><article><h1>\(title)</h1><p>\(body)</p>\(anchors)</article></body></html>"
}

@MainActor
struct CrawlerIntegrationTests {
    @Test func crawlsLocalServerHonoringRobotsAndStandardPolicyBlocksSameURL() async throws {
        let server = try await LocalHTTPServer.start(routes: [
            "/": .init(body: html("Home", links: ["/a", "/private/x"])),
            "/a": .init(body: html("Page A", links: [])),
            "/private/x": .init(body: html("Secret", links: [])),
            "/robots.txt": .init(contentType: "text/plain", body: "User-agent: *\nDisallow: /private/\n"),
        ])
        defer { server.stop() }
        let start = server.url("/")

        // The same URL is rejected by the standard policy.
        #expect(HostPolicy.standard.check(start) != .allowed)
        #expect(HostPolicy.testing(allowLoopback: true).check(start) == .allowed)

        let policy = HostPolicy.testing(allowLoopback: true)
        let crawler = Crawler(
            renderer: WebPageRendering(renderer: WebPageRenderer(policy: policy)),
            robots: RobotsCache(fetcher: URLSessionRobotsFetcher(policy: policy), policy: policy),
            resolver: SystemHostResolver(), policy: policy, limiter: HostRateLimiter(clock: ContinuousClock()))
        var limits = CrawlLimits(depth: 1)
        limits.settle = .milliseconds(100)
        var fetched: [String] = []
        var reasons: [SkipReason] = []
        for try await e in crawler.crawl(start: [start], limits: limits) {
            switch e {
            case .fetched(let p, _): fetched.append(p.url.path)
            case .skipped(_, let r): reasons.append(r)
            case .finished: break
            }
        }
        #expect(fetched == ["/", "/a"])
        #expect(reasons == [.robots])
        #expect(!server.requests.contains { $0.path == "/private/x" })

        // Standard policy: same start URL never reaches the network.
        let before = server.requests.count
        let strict = Crawler(
            renderer: WebPageRendering(renderer: WebPageRenderer(policy: .standard)),
            robots: RobotsCache(fetcher: URLSessionRobotsFetcher(policy: .standard), policy: .standard),
            resolver: SystemHostResolver(), policy: .standard, limiter: HostRateLimiter(clock: ContinuousClock()))
        var strictSkips: [SkipReason] = []
        for try await e in strict.crawl(start: [start], limits: limits) {
            if case .skipped(_, let r) = e { strictSkips.append(r) }
        }
        #expect(strictSkips == [.blockedHost])
        #expect(server.requests.count == before)
    }
}
