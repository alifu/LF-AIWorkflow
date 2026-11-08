//
//  StartupProgress.swift
//  LF-AIWorkflow
//

import Observation
import os

/// Tracks app start-up so the panel can appear in a "starting" state while the login-shell PATH resolves (TD-041).
/// If the composition work hangs, the phase becomes `.failed` after a timeout so the panel can say so (TD-131).
@MainActor
@Observable
final class StartupProgress {
    enum Phase: Sendable, Equatable { case starting, ready, failed }

    /// Generous: the login-shell PATH lookup alone can take 5 s.
    nonisolated static let defaultTimeout = Duration.seconds(30)

    private(set) var phase: Phase = .starting

    /// Runs the slow composition work; `.ready` when it returns, `.failed` (and `nil`) if it exceeds `timeout`.
    /// A hung operation is cancelled but never awaited, so it cannot block the error state.
    /// Complexity: O(1) time beyond `work`, O(1) space
    func run<T: Sendable>(timeout: Duration = StartupProgress.defaultTimeout,
                          _ work: @escaping @Sendable () async -> T) async -> T? {
        let box = OSAllocatedUnfairLock<T?>(initialState: nil)
        await BoundedWait.run(limit: timeout) {
            let value = await work()
            box.withLock { $0 = value }
        }
        let value = box.withLock { $0 }
        phase = value == nil ? .failed : .ready
        return value
    }
}
