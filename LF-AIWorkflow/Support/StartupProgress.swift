//
//  StartupProgress.swift
//  LF-AIWorkflow
//

import Observation

/// Tracks app start-up so the panel can appear in a "starting" state while the login-shell PATH resolves (TD-041).
@MainActor
@Observable
final class StartupProgress {
    enum Phase: Sendable, Equatable { case starting, ready }

    private(set) var phase: Phase = .starting

    /// Runs the slow composition work and flips to `.ready` when it returns.
    /// Complexity: O(1) time beyond `work`, O(1) space
    func run<T>(_ work: () async -> T) async -> T {
        let value = await work()
        phase = .ready
        return value
    }
}
