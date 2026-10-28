//
//  WorkflowViewModel.swift
//  LF-AIWorkflow
//

import AppKit
import Foundation
import Observation

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
    @ObservationIgnored private var board = TaskBoard()
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingUpdate = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var logTask: Task<Void, Never>?

    init(engine: WorkflowEngine, logs: TaskLogStore, clock: any Clock<Duration> = ContinuousClock(),
         now: @escaping @Sendable () -> Date = { Date() }, coalesceInterval: Duration = .milliseconds(100),
         fixLoopCap: Int = EngineSettings.default.fixLoopCap) {
        self.engine = engine
        self.logs = logs
        self.clock = clock
        self.now = now
        self.coalesceInterval = coalesceInterval
        self.fixLoopCap = fixLoopCap
    }

    // MARK: - Lifecycle

    /// Gives the engine new settings for tasks submitted from now on; running tasks keep theirs.
    func applySettings(_ settings: EngineSettings) async {
        await engine.update(settings: settings)
    }

    /// Starts consuming the engine and log streams. Idempotent; call before the first `submit`.
    func start() {
        guard updatesTask == nil else { return }
        let updates = engine.updates
        let changes = logs.changes
        updatesTask = Task { [weak self] in
            for await task in updates {
                guard let self else { return }
                self.receive(task)
            }
        }
        logTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.logRevision &+= 1
            }
        }
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
        if let message = board.apply(task, now: now()) { peek = message }
        if windowTask == nil {
            publish()
            openWindow()
        } else {
            hasPendingUpdate = true
        }
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

    func approve(_ id: UUID) async {
        do { try await engine.approvePlan(id); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func cancel(_ id: UUID) async {
        await engine.cancel(id)
    }

    func resume(_ id: UUID, raising tokens: Int = 0) async {
        do { try await engine.resume(id, raisingBudgetBy: tokens); lastError = nil } catch { lastError = Self.describe(error) }
    }

    func skipTests(_ id: UUID) async {
        do { try await engine.skipTests(id); lastError = nil } catch { lastError = Self.describe(error) }
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
        NSWorkspace.shared.activateFileViewerSelecting([task.workingDirectory])
    }

    func log(for id: UUID) async -> [TaskLogLine] {
        await logs.lines(for: id)
    }

    func task(_ id: UUID) -> WorkflowTask? { board.task(id) }

    private static func describe(_ error: WorkflowError) -> String {
        switch error {
        case .illegalTransition: "That action is not available in the task's current state."
        case .unknownTask: "The task no longer exists."
        case .fixLoopCapReached: "The fix loop limit was reached."
        case .invalidTestTarget(let target): "Invalid test target: \(target)"
        }
    }
}
