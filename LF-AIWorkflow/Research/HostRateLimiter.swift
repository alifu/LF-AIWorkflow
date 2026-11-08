//
//  HostRateLimiter.swift
//  LF-AIWorkflow
//

import Foundation

/// Spaces requests to the same host by at least `minInterval` (or a larger robots crawl-delay).
/// Different hosts are independent. Slots are reserved before sleeping, so concurrent callers queue up.
actor HostRateLimiter {
    private let minInterval: Duration
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var nextSlot: [String: Duration] = [:]

    init<C: Clock & Sendable>(clock: C, minInterval: Duration = .seconds(1)) where C.Duration == Duration {
        let origin = clock.now
        self.minInterval = minInterval
        self.now = { origin.duration(to: clock.now) }
        self.sleep = { try await clock.sleep(for: $0) }
    }

    /// Complexity: O(1) time, O(h) space for h hosts.
    func acquire(host: String, extraDelay: Duration = .zero) async throws {
        let key = host.lowercased()
        let current = now()
        let slot = max(current, nextSlot[key] ?? .zero)
        nextSlot[key] = slot + max(minInterval, extraDelay)
        let wait = slot - current
        if wait > .zero { try await sleep(wait) }
    }
}
