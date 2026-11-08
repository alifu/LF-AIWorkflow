//
//  WorkflowViewModel.swift
//  LF-AIWorkflow
//

import AppKit
import Foundation
import Observation
import os

/// Bridge between the engine actor and the SwiftUI views. The only consumer of `engine.updates` and
/// `logs.changes`; keeps a pure `TaskBoard` and publishes at most one UI update per coalescing window.
@MainActor @Observable
final class WorkflowViewModel {
    private(set) var rows: [TaskRowModel] = []
    private(set) var summary = CollapsedSummary(activeCount: 0, leadStep: nil, attentionCount: 0)
    private(set) var todayTokens = 0
    /// Set when a task enters an attention state; `PeekMessage.sequence` makes repeats distinguishable.
    private(set) var peek: PeekMessage?
    private(set) var lastError: String?
    /// Bumps whenever any task log gained lines; the Terminal tab reloads on it.
    private(set) var logRevision = 0
    /// Peek alerts on or off (TD-005: Settings toggle arrives in Phase 6).
    var showAlerts = true {
        didSet { board.showAlerts = showAlerts }
    }

    @ObservationIgnored private let engine: WorkflowEngine
    @ObservationIgnored private let logs: TaskLogStore
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let coalesceInterval: Duration
    @ObservationIgnored private let fixLoopCap: Int
    @ObservationIgnored private let reviewLoader: any ReviewLoading
    @ObservationIgnored private var board = TaskBoard()
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingUpdate = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var logTask: Task<Void, Never>?

    init(engine: WorkflowEngine, logs: TaskLogStore, clock: any Clock<Duration> = ContinuousClock(),
         now: @escaping @Sendable () -> Date = { Date() }, coalesceInterval: Duration = .milliseconds(100),
         fixLoopCap: Int = EngineSettings.default.fixLoopCap, reviewLoader: any ReviewLoading = FileReviewLoader()) {
        self.engine = engine
        self.logs = logs
        self.clock = clock
        self.now = now
        self.coalesceInterval = coalesceInterval
        self.fixLoopCap = fixLoopCap
        self.reviewLoader = reviewLoader
    }

    // MARK: - Lifecycle

    /// Gives the engine new settings for tasks submitted from now on; running tasks keep theirs.
    func applySettings(_ settings: EngineSettings) async {
        await engine.update(settings: settings)
    }

    /// Starts consuming the engine and log streams. Idempotent; call before the first `submit`.
    private static let logReloadInterval = Duration.milliseconds(100)

    func start() {
        guard updatesTask == nil else { return }
        let engine = engine
        let changes = logs.changes
        updatesTask = Task { [weak self] in
            let updates = await engine.makeUpdates()  // fresh stream per start (TD-115)
            for await task in updates {
                guard let self else { return }
                self.receive(task)
            }
        }
        logTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.logRevision &+= 1
                try? await Task.sleep(for: Self.logReloadInterval)  // throttle: at most ~10 reloads/s (TD-050)
            }
        }
    }

    /// Flushes the engine's pending task save, waiting at most `timeout` (app terminate cannot await).
    /// Complexity: O(n log n) time, O(n) space (n = tasks)
    func flushPersistence(timeout: TimeInterval = 2) {
        let done = DispatchSemaphore(value: 0)
        let engine = engine
        Task.detached { await engine.stop(); done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    func stop() {
        updatesTask?.cancel()
        logTask?.cancel()
        windowTask?.cancel()
        updatesTask = nil
        logTask = nil
        windowTask = nil
    }

    // MARK: - Updates

    /// Applies one engine snapshot. The first update after a quiet period is published at once; updates inside the
    /// window are folded into one publication when it closes (at most 1 / `coalesceInterval` UI updates per second).
    /// Complexity: O(n log n) time per publication (n = tasks), O(n) space
    func receive(_ task: WorkflowTask) {
        if let message = board.apply(task, now: now()) {
            peek = message
        } else if board.awaitsReview(task.id), let file = task.reviewFile {
            loadReviewPeek(taskID: task.id, file: file)
        }
        if windowTask == nil {
            publish()
            openWindow()
        } else {
            hasPendingUpdate = true
        }
    }

    /// Reads the saved review off the main actor, then posts the done peek with its finding count (TD-049).
    /// An unreadable review is logged and the peek stays plain "done".
    /// Complexity: O(review size) time, O(review size) space
    private func loadReviewPeek(taskID: UUID, file: URL) {
        let loader = reviewLoader
        Task { [weak self] in
            var findings: Int?
            do {
                findings = try await loader.load(file).findings.count
            } catch {
                AppLog.workflow.error("saved review could not be read: \(error.localizedDescription, privacy: .public)")
            }
            self?.finishReviewPeek(taskID: taskID, findings: findings)
        }
    }

    private func finishReviewPeek(taskID: UUID, findings: Int?) {
        if let message = board.reviewLoaded(for: taskID, findings: findings) { peek = message }
    }

    /// Shows a short notice in the peek bubble (not tied to a task).
    /// Complexity: O(1) time, O(1) space
    func postNotice(_ text: String) {
        peek = board.notice(text)
    }

    private func openWindow() {
        let (clock, interval) = (clock, coalesceInterval)
        windowTask = Task { [weak self] in
            do { try await clock.sleep(for: interval) } catch { return }
            guard let self else { return }
            self.windowTask = nil
            guard self.hasPendingUpdate else { return }
            self.hasPendingUpdate = false
            self.publish()
            self.openWindow()
        }
    }

    private func publish() {
        let date = now()
        rows = board.rows(now: date, fixLoopCap: fixLoopCap)
        summary = board.summary()
        todayTokens = board.todayTokens(now: date, calendar: .current)
    }

    // MARK: - Commands

    func submit(_ draft: TaskDraft) async {
        _ = await engine.submit(draft)
    }

    /// Returns false (and sets `lastError`) when the engine refuses the approval.
    func approve(_ id: UUID) async -> Bool {
        do { try await engine.approvePlan(id); lastError = nil; return true } catch { lastError = Self.describe(error); return false }
    }

    func cancel(_ id: UUID) async {
        await engine.cancel(id)
    }

    func resume(_ id: UUID, raising tokens: Int = 0) async {
        do { try await engine.resume(id, raisingBudgetBy: tokens); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func retry(_ id: UUID) async {
        do { try await engine.retry(id); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func skipTests(_ id: UUID) async {
        do { try await engine.skipTests(id); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func sendToFix(_ id: UUID, findings: [Finding]) async {
        do { try await engine.sendToFix(id, findings: findings); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func removeWorktree(_ id: UUID) async {
        do { try await engine.removeWorktree(id); lastError = nil } catch { lastError = Self.describe(error) }
    }

    /// Hides finished rows (view model only; the engine keeps the tasks).
    func clearDone() {
        board.clearDone()
        publish()
    }

    func clearError() { lastError = nil }

    /// Reveals the task's worktree (or project) folder in Finder.
    func openWorktree(_ id: UUID) {
        guard let task = board.task(id) else { return }
        EditorOpener().reveal(task.workingDirectory)
    }

    func log(for id: UUID) async -> [TaskLogLine] {
        await logs.tail(for: id, limit: TerminalText.defaultTail).lines
    }

    func task(_ id: UUID) -> WorkflowTask? { board.task(id) }

    private static func describe(_ error: WorkflowError) -> String {
        switch error {
        case .illegalTransition: "That action is not available in the task's current state."
        case .unknownTask: "The task no longer exists."
        case .fixLoopCapReached: "The fix loop limit was reached."
        case .invalidTestTarget(let target): "Invalid test target: \(target)"
        case .noFindings: "There are no findings to send to Fix."
        case .taskActive: "Finish or cancel the task before removing its worktree."
        case .noWorktree: "This task has no worktree."
        case .worktreeRemovalFailed(let reason): "Cannot remove the worktree: \(reason)"
        case .worktreeMissing(let path): "The worktree no longer exists: \(path)"
        }
    }
}
