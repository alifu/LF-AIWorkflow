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
    static func withLock<T, E: Error>(_ body: () throws(E) -> T) throws(E) -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Concurrent queue for spawns: waiting for the lock or a slow exec parks this thread, never a Swift concurrency
    /// thread. Concurrent so slow first execs overlap (TD-120); mutual exclusion is `withLock`'s job.
    private static let spawnQueue = DispatchQueue(label: "com.alifu.LF-AIWorkflow.spawn", attributes: .concurrent)

    /// Runs `body` on `spawnQueue` and resumes the caller with its result. Use this from async code: a spawn can
    /// take hundreds of milliseconds, and blocking a cooperative thread for that long starves every other task
    /// (TD-055 follow-up). `body` takes `withLock` itself where it spawns; this function must not, since the lock
    /// is not recursive.
    /// Complexity: O(1) time beyond `body`, O(1) space
    static func runOffPool<T: Sendable, E: Error>(_ body: @escaping @Sendable () throws(E) -> T) async throws(E) -> T {
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, E>, Never>) in
            spawnQueue.async {
                do throws(E) {
                    continuation.resume(returning: .success(try body()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        return try outcome.get()
    }
}
