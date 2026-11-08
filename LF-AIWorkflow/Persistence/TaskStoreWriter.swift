//
//  TaskStoreWriter.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// The only place the engine's blocking file I/O happens (TD-123, TD-108): debounced task saves, the task
/// file load, plan and review file writes, and the worktree existence check. The engine never waits for disk
/// on `publish`: `schedule` only stores the latest snapshot in a mailbox and wakes a single drain.
actor TaskStoreWriter {
    /// Quiet period before a scheduled snapshot is written.
    static let defaultDebounce: Duration = .milliseconds(300)

    private struct Mailbox {
        var pending: [WorkflowTask]?
        var drainScheduled = false
    }

    private let store: (any TaskPersisting)?
    private let debounce: Duration
    private let mailbox = OSAllocatedUnfairLock(initialState: Mailbox())

    /// Complexity: O(1) time, O(1) space
    init(store: (any TaskPersisting)?, debounce: Duration = TaskStoreWriter.defaultDebounce) {
        self.store = store
        self.debounce = debounce
    }

    /// Remembers `tasks` as the snapshot to write; a newer call before the write replaces it (coalescing).
    /// Never blocks on disk.
    /// Complexity: O(1) time, O(n) space (the snapshot is held until written)
    nonisolated func schedule(_ tasks: [WorkflowTask]) {
        guard store != nil else { return }
        let startDrain = mailbox.withLock { box -> Bool in
            box.pending = tasks
            if box.drainScheduled { return false }
            box.drainScheduled = true
            return true
        }
        if startDrain { Task { await self.drain() } }
    }

    /// Writes any pending snapshot now (engine stop, app terminate). A no-op when nothing is pending.
    /// Complexity: O(n log n) time, O(n) space (n = tasks, via the store)
    func flush() {
        writePending()
    }

    /// Complexity: O(n) time, O(n) space (n = stored tasks)
    func load() -> [WorkflowTask] {
        store?.load() ?? []
    }

    /// `SafeProjectFile.write` on the writer, so the no-follow symlink checks (TD-098) still apply.
    /// Complexity: O(d + size) time, O(size) space
    func writeProjectFile(_ text: String, to relativeDirectory: String, name: String, root: URL) throws -> URL {
        try SafeProjectFile.write(text, to: relativeDirectory, name: name, root: root)
    }

    /// Saves a parsed review report (slug validation and no-follow checks live in `ReviewReport.save`).
    /// Complexity: O(size) time, O(size) space
    func saveReview(_ report: ReviewReport, projectRoot: URL, slug: String) throws -> URL {
        try report.save(projectRoot: projectRoot, slug: slug)
    }

    /// Complexity: O(1) time, O(1) space
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func drain() async {
        try? await Task.sleep(for: debounce)
        // Take the snapshot and clear the flag under one lock, so a schedule racing this call starts a new drain.
        let tasks = mailbox.withLock { box -> [WorkflowTask]? in
            box.drainScheduled = false
            defer { box.pending = nil }
            return box.pending
        }
        if let tasks { store?.save(tasks) }
    }

    private func writePending() {
        let tasks = mailbox.withLock { box -> [WorkflowTask]? in
            defer { box.pending = nil }
            return box.pending
        }
        if let tasks { store?.save(tasks) }
    }
}
