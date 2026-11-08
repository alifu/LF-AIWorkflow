//
//  HostResolver.swift
//  LF-AIWorkflow
//

import Foundation
import Darwin
import os

/// A resolved or literal IP address.
nonisolated enum IPAddress: Sendable, Equatable {
    case v4(UInt32)
    case v6([UInt8])
}

nonisolated protocol HostResolving: Sendable {
    func addresses(for host: String) async throws -> [IPAddress]
}

nonisolated enum HostResolveError: Error, Sendable, Equatable {
    case failed
    case timedOut
}

/// `getaddrinfo` on a background queue with a hard time cap.
///
/// Known residual (TD-090, accepted, documented): DNS rebinding. The addresses checked here are
/// not pinned to the connection. A hostile DNS server can return a public address for the check
/// and a private one when WebKit or the crawler connects. The window is the gap between this
/// lookup and the connect. Pinning is not done because WKWebView does not expose the connected
/// IP, so a pinned lookup would not cover page loads and would add a second code path to keep in
/// sync. Mitigations in place:
/// - `HostPolicy.check(_:)` rejects non-http(s) schemes, userinfo, non-80/443 ports, local suffixes
///   and literal private or loopback hosts before any lookup.
/// - `HostPolicy.check(addresses:)` rejects any resolved private, loopback, or link-local address.
/// - `Crawler.fetch` resolves and checks each host before fetching it.
/// - `WebPageRenderer` `NavigationGate` re-resolves and re-checks every main-frame hop, including
///   redirects (`hopAllowed`, TD-076), and blocks downloads and disallowed subframes.
/// - Lookups are capped at `timeout` (3 s), and a failed or timed-out lookup blocks the fetch.
/// Complexity: O(1) time, O(1) space (documentation only).
nonisolated struct SystemHostResolver: HostResolving {
    static let timeout: Duration = .seconds(3)

    private let timeout: Duration
    private let lookup: @Sendable (String) throws -> [IPAddress]

    /// `lookup` and `timeout` are seams for tests; production uses `getaddrinfo` and 3 s.
    init(timeout: Duration = SystemHostResolver.timeout,
         lookup: @escaping @Sendable (String) throws -> [IPAddress] = SystemHostResolver.systemLookup) {
        self.timeout = timeout
        self.lookup = lookup
    }

    /// Races the blocking lookup against the timeout; the caller returns at the timeout even if
    /// `getaddrinfo` is still blocked (its thread finishes later and its result is dropped).
    /// Complexity: O(a) time, O(a) space for a resolved addresses.
    func addresses(for host: String) async throws -> [IPAddress] {
        let timeout = self.timeout
        let lookup = self.lookup
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[IPAddress], Error>) in
            let once = ResumeOnce(cont)
            once.setTimer(Task {
                try? await Task.sleep(for: timeout)
                once.resume(.failure(HostResolveError.timedOut))
            })
            DispatchQueue.global(qos: .utility).async {
                once.resume(Result { try lookup(host) })
            }
        }
    }

    /// Resumes its continuation exactly once; later results are dropped.
    private final class ResumeOnce: Sendable {
        private struct State {
            var continuation: CheckedContinuation<[IPAddress], Error>?
            var timer: Task<Void, Never>?
            var done = false
        }
        private let state: OSAllocatedUnfairLock<State>

        init(_ c: CheckedContinuation<[IPAddress], Error>) {
            state = OSAllocatedUnfairLock(initialState: State(continuation: c))
        }

        func setTimer(_ t: Task<Void, Never>) {
            let cancelNow = state.withLock { s -> Bool in
                if s.done { return true }
                s.timer = t
                return false
            }
            if cancelNow { t.cancel() }
        }

        func resume(_ result: Result<[IPAddress], Error>) {
            let (c, t) = state.withLock { s -> (CheckedContinuation<[IPAddress], Error>?, Task<Void, Never>?) in
                guard !s.done else { return (nil, nil) }
                s.done = true
                defer { s.continuation = nil; s.timer = nil }
                return (s.continuation, s.timer)
            }
            t?.cancel()
            c?.resume(with: result)
        }
    }

    /// Complexity: O(a) time, O(a) space.
    static func systemLookup(_ host: String) throws -> [IPAddress] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let first = head else {
            throw HostResolveError.failed
        }
        defer { freeaddrinfo(head) }
        var out: [IPAddress] = []
        var cur: UnsafeMutablePointer<addrinfo>? = first
        while let node = cur {
            if let addr = node.pointee.ai_addr {
                if node.pointee.ai_family == AF_INET {
                    let s = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    out.append(.v4(UInt32(bigEndian: s.sin_addr.s_addr)))
                } else if node.pointee.ai_family == AF_INET6 {
                    let s = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                    out.append(.v6(withUnsafeBytes(of: s.sin6_addr) { Array($0) }))
                }
            }
            cur = node.pointee.ai_next
        }
        return out
    }
}
