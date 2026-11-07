//
//  BoundedWait.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Runs an operation but stops waiting for it after a time limit or when the caller is cancelled.
/// The operation's own task is cancelled in both cases (so a child process can be killed) but never awaited: a shared, deduped
/// operation (GraphifyClient.refresh) may ignore cancellation and is bounded by its own timeout (TD-129 won't fix).
nonisolated enum BoundedWait {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var finished = false
    }

    /// Complexity: O(1) time (plus the wait), O(1) space
    static func run(limit: Duration, _ operation: @escaping @Sendable () async -> Void) async {
        let state = OSAllocatedUnfairLock(initialState: State())
        let work = Task { await operation(); finish(state) }
        let timer = Task { try? await Task.sleep(for: limit); finish(state) }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyDone = state.withLock { state -> Bool in
                    if state.finished { return true }
                    state.continuation = continuation
                    return false
                }
                if alreadyDone { continuation.resume() }
            }
        } onCancel: {
            finish(state)
        }
        work.cancel()
        timer.cancel()
    }

    private static func finish(_ state: OSAllocatedUnfairLock<State>) {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.finished = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}
