//
//  SpawnGate.swift
//  LF-AIWorkflow
//

import os

/// The only place the app forks/posix_spawns. Every `lf_pty_spawn` and `Process.run()` goes through it,
/// so no concurrent fork can inherit another spawn's not-yet-CLOEXEC descriptors (TD-014).
nonisolated enum SpawnGate {
    private static let lock = OSAllocatedUnfairLock()

    /// Runs `body` while holding the app-wide spawn lock. Keep `body` short.
    /// Complexity: O(1) time (plus `body`), O(1) space
    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
