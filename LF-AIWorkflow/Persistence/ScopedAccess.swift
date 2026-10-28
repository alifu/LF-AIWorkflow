//
//  ScopedAccess.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Balances `startAccessingSecurityScopedResource` / `stop...`: access ends on `release()` or deinit, whichever is first.
nonisolated final class ScopedAccess: Sendable {
    struct Hooks: Sendable {
        let start: @Sendable (URL) -> Bool
        let stop: @Sendable (URL) -> Void

        static let system = Hooks(start: { $0.startAccessingSecurityScopedResource() },
                                  stop: { $0.stopAccessingSecurityScopedResource() })
    }

    let url: URL
    private let hooks: Hooks
    private let isActive: OSAllocatedUnfairLock<Bool>

    /// Complexity: O(1) time, O(1) space
    init(url: URL, hooks: Hooks = .system) {
        self.url = url
        self.hooks = hooks
        isActive = OSAllocatedUnfairLock(initialState: hooks.start(url))
    }

    /// Complexity: O(1) time, O(1) space
    func release() {
        let wasActive = isActive.withLock { active in
            defer { active = false }
            return active
        }
        if wasActive { hooks.stop(url) }
    }

    deinit { release() }
}
