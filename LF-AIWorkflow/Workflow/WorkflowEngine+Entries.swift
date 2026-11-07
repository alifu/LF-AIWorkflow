//
//  WorkflowEngine+Entries.swift
//  LF-AIWorkflow
//

import Foundation

extension WorkflowEngine {
    /// `done -> fix`: feeds saved review findings into one more Fix stage, then the usual test and review loop
    /// runs again (TD-045). The caller picks the findings (the review screen sends HIGH and above).
    /// Complexity: O(f) time, O(f) space (f = findings)
    func sendToFix(_ id: UUID, findings: [Finding]) async throws(WorkflowError) {
        var task = try lookup(id)
        guard task.state == .done else { throw .illegalTransition(from: task.state, to: .fix) }
        guard !findings.isEmpty else { throw .noFindings }
        if let worktree = task.worktree, !(await writer.fileExists(at: worktree.path)) {
            throw .worktreeMissing(worktree.path.path)
        }
        // The check suspended: another call may have moved the task meanwhile.
        task = try lookup(id)
        guard task.state == .done else { throw .illegalTransition(from: task.state, to: .fix) }
        taskSettings[id] = settings
        findingsForFix[id] = findings
        publish(try TaskTransitions.move(task.with(lastErrors: nil), to: .fix, fixLoopCap: settings.fixLoopCap))
        startDriving(id)
    }

    /// Removes the task's git worktree (forced: the user confirmed in the UI; the branch stays) and clears the
    /// task's worktree field. Refused unless the task is done or cancelled (a failed task may still be retried in it) (TD-046).
    /// Complexity: O(1) time, O(1) space (plus the git calls)
    func removeWorktree(_ id: UUID) async throws(WorkflowError) {
        let task = try lookup(id)
        guard task.state == .done || task.state == .cancelled else { throw .taskActive(id) }
        guard let worktree = task.worktree else { throw .noWorktree(id) }
        do {
            try await deps.worktrees.remove(worktree, repo: task.projectRoot, force: true)
        } catch {
            throw .worktreeRemovalFailed(Self.describe(error))
        }
        update(id) { $0.with(worktree: nil) }
        await log("Removed worktree \(worktree.path.path)", id, task.state)
    }
}
