//
//  RenderGuardTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
import WebKit
@testable import LF_AIWorkflow

@MainActor
struct RenderGuardTests {
    private func blocked(_ url: String) throws -> Bool {
        try WebPageRenderer.blockedURLFilters.contains {
            let re = try NSRegularExpression(pattern: $0)
            return re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
    }

    @Test(arguments: ["http://[::1]/", "https://[fc00::1]/x", "http://printer.local/", "http://svc.internal:8080/",
                      "http://100.64.0.1/", "http://100.127.255.1/", "http://0.1.2.3/", "http://127.0.0.1/",
                      "http://10.0.0.1/", "http://localhost/", "ftp://x/"])
    func blockListCoversPrivateTargets(url: String) throws {
        #expect(try blocked(url))
    }

    @Test(arguments: ["https://example.com/", "https://100.128.0.1/", "https://100.63.0.1/", "https://localdomain.com/",
                      "https://internal.example.com/", "https://example.com/?u=http://[::1]/"])
    func blockListLeavesPublicHosts(url: String) throws {
        #expect(!(try blocked(url)))
    }

    @Test func blockRulesCompile() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "lf-test-block", encodedContentRuleList: WebPageRenderer.blockRules)
        #expect(list != nil)
    }

    @Test func subframeNavigationIsPolicyChecked() {
        let policy = HostPolicy.standard
        #expect(!WebPageRenderer.allowsSubframe(URL(string: "http://127.0.0.1:8080/")!, policy: policy))
        #expect(!WebPageRenderer.allowsSubframe(URL(string: "http://[::1]/")!, policy: policy))
        #expect(!WebPageRenderer.allowsSubframe(URL(string: "file:///etc/passwd")!, policy: policy))
        #expect(WebPageRenderer.allowsSubframe(URL(string: "about:blank")!, policy: policy))
        #expect(WebPageRenderer.allowsSubframe(URL(string: "https://example.com/")!, policy: policy))
    }

    @Test func renderWithBlockedIframeStillCompletes() async throws {
        let html = "<html><body><p>hello</p><iframe src=\"http://127.0.0.1:9/x\"></iframe></body></html>"
        let page = try await WebPageRenderer(policy: .standard).render(html: html)
        #expect(page.text.contains("hello"))
    }
}

struct HostResolverTimeoutTests {
    @Test func slowLookupReturnsAtTimeout() async throws {
        let resolver = SystemHostResolver(timeout: .milliseconds(200)) { _ in
            Thread.sleep(forTimeInterval: 3)
            return [.v4(1)]
        }
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: HostResolveError.timedOut) { _ = try await resolver.addresses(for: "slow.test") }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func fastLookupReturnsAddresses() async throws {
        let resolver = SystemHostResolver(timeout: .seconds(2)) { _ in [.v4(0x01020304)] }
        #expect(try await resolver.addresses(for: "x.test") == [.v4(0x01020304)])
    }

    @Test func lookupFailurePropagates() async {
        let resolver = SystemHostResolver(timeout: .seconds(2)) { _ in throw HostResolveError.failed }
        await #expect(throws: HostResolveError.failed) { _ = try await resolver.addresses(for: "x.test") }
    }
}

private struct HopResolver: HostResolving {
    var map: [String: [LF_AIWorkflow.IPAddress]]
    func addresses(for host: String) async throws -> [LF_AIWorkflow.IPAddress] {
        guard let a = map[host] else { throw HostResolveError.failed }
        return a
    }
}

@MainActor
struct RenderHopSafetyTests {
    @Test func redirectHopResolvingToPrivateIPIsRejected() async {
        let r = HopResolver(map: ["evil.example.com": [.v4(0x0A000005)]])
        #expect(!(await WebPageRenderer.hopAllowed(URL(string: "https://evil.example.com/")!, policy: .standard, resolver: r)))
    }

    @Test func hopWithUnresolvableHostIsRejected() async {
        #expect(!(await WebPageRenderer.hopAllowed(URL(string: "https://nx.example.com/")!, policy: .standard,
                                                  resolver: HopResolver(map: [:]))))
    }

    @Test func hopResolvingPublicIsAllowed() async {
        let r = HopResolver(map: ["ok.example.com": [.v4(0x5DB8D822)]])
        #expect(await WebPageRenderer.hopAllowed(URL(string: "https://ok.example.com/")!, policy: .standard, resolver: r))
    }

    @Test func cancelledLoadReturnsImmediately() async {
        let gate = NavigationGate(policy: .standard, resolver: HopResolver(map: [:]), allowedFirst: nil)
        let view = WKWebView(frame: .zero)
        let task = Task { @MainActor in try await gate.load(view, timeout: .seconds(60)) { _ in } }
        try? await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - started < .seconds(5))
        if case .failure(let e) = result { #expect(e is CancellationError) } else { Issue.record("expected cancellation") }
    }

    @Test func finalURLMismatchOrPrivateIsRejected() {
        let page = URL(string: "https://example.com/a")!
        let p = HostPolicy.standard
        #expect(WebPageRenderer.finalURLMatches(viewURL: URL(string: "https://example.com/a#x"), pageURL: page, policy: p, fixture: false))
        #expect(!WebPageRenderer.finalURLMatches(viewURL: URL(string: "https://example.com/b"), pageURL: page, policy: p, fixture: false))
        #expect(!WebPageRenderer.finalURLMatches(viewURL: URL(string: "http://127.0.0.1/a"), pageURL: page, policy: p, fixture: false))
        #expect(!WebPageRenderer.finalURLMatches(viewURL: nil, pageURL: page, policy: p, fixture: false))
    }
}
