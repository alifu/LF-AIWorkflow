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

    static let fixtureBase = URL(string: "https://fixture.test/")!

    private let policy: HostPolicy
    init(policy: HostPolicy = .standard) { self.policy = policy }

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
        let delegate = NavigationGate(policy: policy, allowedFirst: allowedFirst)
        view.navigationDelegate = delegate
        defer { view.navigationDelegate = nil; view.stopLoading() }

        try await delegate.load(view, timeout: timeout, start: start)
        try await Task.sleep(for: settle)
        let result: Any?
        do { result = try await view.evaluateJavaScript(script) } catch { throw CaptureError.renderFailed(String(describing: error)) }
        guard let json = result as? String else { throw CaptureError.malformed }
        return try CapturedPage.parse(json, policy: policy)
    }
}

/// Re-checks every navigation with `HostPolicy`; bridges delegate callbacks to async via one continuation.
@MainActor
private final class NavigationGate: NSObject, WKNavigationDelegate {
    private let policy: HostPolicy
    private var allowedFirst: URL?
    private var continuation: CheckedContinuation<Void, Error>?

    init(policy: HostPolicy, allowedFirst: URL?) {
        self.policy = policy
        self.allowedFirst = allowedFirst
    }

    func load(_ view: WKWebView, timeout: Duration, start: (WKWebView) -> Void) async throws {
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finish(.failure(CaptureError.timedOut))
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            start(view)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

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
        if policy.check(url) == .allowed { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        finish(.failure(CaptureError.blockedNavigation))
    }

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
