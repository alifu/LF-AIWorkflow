//
//  WebPageRenderer.swift
//  LF-AIWorkflow
//

import Foundation
import WebKit

/// Offscreen, non-persistent web view that renders a page and runs the bundled read-only `extract.js`.
@MainActor
final class WebPageRenderer {
    /// url-filter regexes (WebKit subset, one rule each) for hosts that must never load, including subframes.
    static let blockedURLFilters: [String] = {
        // WebKit's regex subset has no alternation, so each alternative is its own rule.
        var f = [#"^https?://localhost"#, #"^https?://[^/:?#]*\.localhost"#,
                 #"^https?://127\."#, #"^https?://10\."#, #"^https?://192\.168\."#, #"^https?://169\.254\."#,
                 #"^https?://172\.1[6-9]\."#, #"^https?://172\.2[0-9]\."#, #"^https?://172\.3[01]\."#,
                 #"^https?://100\.6[4-9]\."#, #"^https?://100\.[7-9][0-9]\."#,
                 #"^https?://100\.1[01][0-9]\."#, #"^https?://100\.12[0-7]\."#,
                 #"^https?://0\."#, #"^https?://\["#]
        for tld in ["local", "internal"] {
            f.append(#"^https?://[^/:?#]*\."# + tld + #"[/:?#]"#)
            f.append(#"^https?://[^/:?#]*\."# + tld + "$")
        }
        for scheme in ["ftp", "file", "ws", "wss"] { f.append("^" + scheme + ":") }
        return f
    }()

    /// Complexity: O(r * L) time, O(r * L) space (r = block rules, L = longest rule)
    static var blockRules: String {
        let rules = blockedURLFilters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Navigation decision shared by main frame and subframes. Complexity: O(1) time, O(1) space
    nonisolated static func allowsSubframe(_ url: URL, policy: HostPolicy) -> Bool {
        let s = url.absoluteString
        if s == "about:blank" || s == "about:srcdoc" { return true }
        return policy.check(url) == .allowed
    }

    nonisolated static let fixtureBase = URL(string: "https://fixture.test/")!

    /// Whether a hop's host resolves only to allowed addresses (TD-076). Complexity: O(a) time, O(a) space
    nonisolated static func hopAllowed(_ url: URL, policy: HostPolicy, resolver: any HostResolving) async -> Bool {
        guard policy.check(url) == .allowed, let host = url.host(percentEncoded: true) else { return false }
        guard let addresses = try? await resolver.addresses(for: host) else { return false }
        return policy.check(addresses: addresses) == .allowed
    }

    /// The page the view ended on must still be allowed and match the extracted URL (TD-100).
    /// Complexity: O(1) time, O(1) space
    nonisolated static func finalURLMatches(viewURL: URL?, pageURL: URL, policy: HostPolicy, fixture: Bool) -> Bool {
        guard let viewURL else { return false }
        if fixture { return viewURL == fixtureBase }
        guard policy.check(viewURL) == .allowed else { return false }
        func stripped(_ u: URL) -> String {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
            c?.fragment = nil
            return c?.string ?? u.absoluteString
        }
        return stripped(viewURL) == stripped(pageURL)
    }

    private let policy: HostPolicy
    private let resolver: any HostResolving
    init(policy: HostPolicy = .standard, resolver: any HostResolving = SystemHostResolver()) {
        self.policy = policy
        self.resolver = resolver
    }

    /// Complexity: O(page size) time, O(page size) space
    func render(_ url: URL, settle: Duration = .milliseconds(1500), timeout: Duration = .seconds(30)) async throws -> CapturedPage {
        guard policy.check(url) == .allowed else { throw CaptureError.blockedNavigation }
        return try await run(settle: settle, timeout: timeout, allowedFirst: nil) { $0.load(URLRequest(url: url)) }
    }

    /// Renders literal HTML (tests). Complexity: O(html size) time, O(html size) space
    func render(html: String, settle: Duration = .milliseconds(100), timeout: Duration = .seconds(20)) async throws -> CapturedPage {
        try await run(settle: settle, timeout: timeout, allowedFirst: Self.fixtureBase) {
            $0.loadHTMLString(html, baseURL: Self.fixtureBase)
        }
    }

    /// Loads, settles, runs `extract.js`, and checks the final URL. Waits up to `timeout` for the load.
    /// Complexity: O(p) time, O(p) space (p = extracted page JSON bytes); the load wait is bounded by `timeout`
    private func run(settle: Duration, timeout: Duration, allowedFirst: URL?,
                     start: (WKWebView) -> Void) async throws -> CapturedPage {
        guard let scriptURL = Bundle.main.url(forResource: "extract", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { throw CaptureError.scriptMissing }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if !policy.allowLoopback {
            do {
                guard let list = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "lf-research-block-v2", encodedContentRuleList: Self.blockRules) else {
                    throw CaptureError.renderFailed("block list unavailable")
                }
                config.userContentController.add(list)
            } catch let error as CaptureError {
                throw error
            } catch {
                throw CaptureError.renderFailed("block list: \(error.localizedDescription)")
            }
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        let delegate = NavigationGate(policy: policy, resolver: resolver, allowedFirst: allowedFirst)
        view.navigationDelegate = delegate
        defer { view.navigationDelegate = nil; view.stopLoading() }

        try await delegate.load(view, timeout: timeout, start: start)
        try await Task.sleep(for: settle)
        let result: Any?
        do {
            result = try await view.evaluateJavaScript(script, in: nil, contentWorld: .defaultClient)
        } catch { throw CaptureError.renderFailed(String(describing: error)) }
        guard let json = result as? String else { throw CaptureError.malformed }
        let page = try CapturedPage.parse(json, policy: policy)
        guard Self.finalURLMatches(viewURL: view.url, pageURL: page.url, policy: policy, fixture: allowedFirst != nil) else {
            throw CaptureError.blockedNavigation
        }
        return page
    }
}

/// Re-checks every navigation with `HostPolicy`; bridges delegate callbacks to async via one continuation.
@MainActor
final class NavigationGate: NSObject, WKNavigationDelegate {
    private let policy: HostPolicy
    private let resolver: any HostResolving
    private var allowedFirst: URL?
    private var continuation: CheckedContinuation<Void, Error>?

    init(policy: HostPolicy, resolver: any HostResolving, allowedFirst: URL?) {
        self.policy = policy
        self.resolver = resolver
        self.allowedFirst = allowedFirst
    }

    /// Starts one navigation and suspends until the delegate finishes it or `timeout` elapses.
    /// Complexity: O(1) time, O(1) space (the timer and continuation are constant-size)
    func load(_ view: WKWebView, timeout: Duration, start: (WKWebView) -> Void) async throws {
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finish(.failure(CaptureError.timedOut))
        }
        defer { timer.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()); return }
                continuation = c
                start(view)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    /// Resumes the pending continuation once; later calls are no-ops.
    /// Complexity: O(1) time, O(1) space
    private func finish(_ result: Result<Void, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    /// Blocks downloads and disallowed hops; main-frame hops are then resolved before they are allowed.
    /// Complexity: O(1) time, O(1) space to decide synchronously (the async resolution is O(a), a = resolved addresses)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { return decisionHandler(.cancel) }
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        guard navigationAction.targetFrame?.isMainFrame ?? true else {
            return decisionHandler(WebPageRenderer.allowsSubframe(url, policy: policy) ? .allow : .cancel)
        }
        if let first = allowedFirst {
            allowedFirst = nil
            if url == first || url.absoluteString == "about:blank" { return decisionHandler(.allow) }
        }
        // Every main-frame hop (including redirects) is resolved and re-checked before it is followed.
        guard policy.check(url) == .allowed else {
            decisionHandler(.cancel)
            return finish(.failure(CaptureError.blockedNavigation))
        }
        let policy = self.policy, resolver = self.resolver
        Task { @MainActor [weak self] in
            if await WebPageRenderer.hopAllowed(url, policy: policy, resolver: resolver) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                self?.finish(.failure(CaptureError.blockedNavigation))
            }
        }
    }

    /// Complexity: O(1) time, O(1) space
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(CaptureError.renderFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(CaptureError.renderFailed(error.localizedDescription)))
    }
}
