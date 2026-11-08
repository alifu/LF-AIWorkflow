//
//  RobotsCache.swift
//  LF-AIWorkflow
//

import Foundation
import os

nonisolated struct RobotsFetchResult: Sendable, Equatable {
    let status: Int
    let body: String
}

nonisolated protocol RobotsFetching: Sendable {
    func fetch(_ url: URL) async throws -> RobotsFetchResult
}

/// One robots.txt fetch per scheme+host per crawl. Status mapping: 2xx parse, 4xx allow all,
/// anything else (5xx, network error, timeout) disallow all.
actor RobotsCache {
    static let minDelay: Duration = .seconds(1)
    static let maxDelay: Duration = .seconds(10)

    private let fetcher: any RobotsFetching
    private let policy: HostPolicy
    private var entries: [String: RobotsRules] = [:]

    init(fetcher: any RobotsFetching, policy: HostPolicy) {
        self.fetcher = fetcher
        self.policy = policy
    }

    /// Complexity: O(1) amortized lookup plus one network fetch per origin; O(h) space for h origins.
    func isAllowed(_ url: URL) async -> Bool {
        guard let rules = await rules(for: url) else { return false }
        var path = url.path(percentEncoded: true)
        if path.isEmpty { path = "/" }
        if let query = url.query(percentEncoded: true) { path += "?" + query }
        return rules.allows(path: path)
    }

    /// Delay between requests to the origin: max(1 s, crawl-delay), capped at 10 s.
    func delay(for url: URL) async -> Duration {
        let requested = await rules(for: url)?.crawlDelay ?? Self.minDelay
        return min(Self.maxDelay, max(Self.minDelay, requested))
    }

    private func rules(for url: URL) async -> RobotsRules? {
        guard policy.check(url).isAllowed, let scheme = url.scheme?.lowercased(),
              let host = url.host(percentEncoded: true)?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        let key = "\(scheme)://\(host)\(port)"
        if let cached = entries[key] { return cached }
        guard let robotsURL = URL(string: key + "/robots.txt") else { return nil }
        let parsed: RobotsRules
        do {
            let result = try await fetcher.fetch(robotsURL)
            switch result.status {
            case 200..<300: parsed = RobotsRules.parse(result.body)
            case 400..<500: parsed = .allowAll
            default: parsed = .disallowAll
            }
        } catch {
            parsed = .disallowAll
        }
        entries[key] = parsed
        return parsed
    }
}

/// Ephemeral-session fetcher: no cookies, 10 s timeout, max 5 same-host redirects, each re-checked.
nonisolated final class URLSessionRobotsFetcher: RobotsFetching {
    static let timeout: TimeInterval = 10
    static let maxRedirects = 5
    private static let maxBodyBytes = RobotsRules.maxInputBytes

    private let policy: HostPolicy

    init(policy: HostPolicy) { self.policy = policy }

    /// Complexity: O(n) time and space for body size n (capped).
    func fetch(_ url: URL) async throws -> RobotsFetchResult {
        guard policy.check(url).isAllowed else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = Self.timeout
        let session = URLSession(configuration: config, delegate: Redirects(policy: policy, host: url.host()), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue(RobotsRules.productToken, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let body = String(decoding: data.prefix(Self.maxBodyBytes), as: UTF8.self)
        return RobotsFetchResult(status: http.statusCode, body: body)
    }

    private final class Redirects: NSObject, URLSessionTaskDelegate, Sendable {
        let policy: HostPolicy
        let host: String?
        private let hops = OSAllocatedUnfairLock(initialState: 0)
        init(policy: HostPolicy, host: String?) { self.policy = policy; self.host = host }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            let hop = hops.withLock { $0 += 1; return $0 }
            guard hop <= URLSessionRobotsFetcher.maxRedirects, let url = request.url, policy.check(url).isAllowed,
                  url.host()?.lowercased() == host?.lowercased() else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}
