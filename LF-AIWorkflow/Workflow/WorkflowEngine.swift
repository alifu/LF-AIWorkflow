//
//  WorkflowEngine.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Drives tasks through `queued -> plan -> approval -> code -> (test <-> fix)* -> review -> done`.
/// All state lives in this actor; every change is a new immutable `WorkflowTask` published on `updates`.
/// One driver `Task` per running task; `cancel` cancels it, which ends the Claude stream (killing the child)
/// and the test run. Stage handlers live in `WorkflowEngine+Stages.swift`.
actor WorkflowEngine {
    nonisolated let updates: AsyncStream<WorkflowTask>
    private let continuation: AsyncStream<WorkflowTask>.Continuation

    let deps: EngineDependencies
    /// Settings for tasks submitted from now on. Tasks already submitted keep their copy in `taskSettings`.
    private(set) var settings: EngineSettings
    /// Snapshot taken at submit; every stage of that task reads it, so a Settings change never reaches a running task.
    private var taskSettings: [UUID: EngineSettings] = [:]
    var tasks: [UUID: WorkflowTask] = [:]
    var budgets: [UUID: TokenBudget] = [:]
    var testCommands: [UUID: TestCommand] = [:]
    /// Fingerprint of each task's test entry point as the Code stage started (see `TestEntryGuard`).
    var entryFingerprints: [UUID: String] = [:]
    /// Base revision for the review diff when no worktree is used.
    var baseCommits: [UUID: String] = [:]
    private var drivers: [UUID: Task<Void, Never>] = [:]

    init(dependencies: EngineDependencies, settings: EngineSettings) {
        deps = dependencies
        self.settings = settings
        (updates, continuation) = AsyncStream.makeStream(of: WorkflowTask.self, bufferingPolicy: .unbounded)
    }

    deinit {
        continuation.finish()
        for driver in drivers.values { driver.cancel() }
    }

    // MARK: - Public API

    /// Complexity: O(1) time, O(1) space
    func submit(_ draft: TaskDraft) -> UUID {
        let task = WorkflowTask(
            id: UUID(), title: draft.title, slug: WorktreeManager.slug(for: draft.title), prompt: draft.prompt,
            projectRoot: draft.projectRoot, documents: draft.documents, skillDirs: draft.skillDirs, state: .queued,
            resumeState: nil, waitReason: nil, failure: nil, worktree: nil, sessionId: nil, planFile: nil,
            fixAttempts: 0, usageByStage: [:], lastErrors: nil, testCommandDisplay: nil, reviewFile: nil,
            createdAt: Date())
        taskSettings[task.id] = settings
        publish(task)
        startDriving(task.id)
        return task.id
    }

    /// `awaitingApproval -> code`.
    /// Complexity: O(1) time, O(1) space
    func approvePlan(_ id: UUID) throws(WorkflowError) {
        let task = try lookup(id)
        publish(try TaskTransitions.move(task, to: .code, fixLoopCap: effectiveSettings(for: id).fixLoopCap))
        startDriving(id)
    }

    /// `awaitingInput -> resumeState`, optionally with a larger token budget.
    /// Complexity: O(1) time, O(1) space
    func resume(_ id: UUID, raisingBudgetBy tokens: Int = 0) throws(WorkflowError) {
        let task = try lookup(id)
        guard task.state == .awaitingInput, let target = task.resumeState else {
            throw .illegalTransition(from: task.state, to: task.resumeState ?? .awaitingInput)
        }
        let moved = try TaskTransitions.move(task, to: target, fixLoopCap: effectiveSettings(for: id).fixLoopCap)
        if case .testEntryModified = task.waitReason { acceptCurrentTestEntryPoint(id) }
        if tokens > 0 { budgets[id] = (budgets[id] ?? effectiveSettings(for: id).budget).raising(by: tokens) }
        publish(moved)
        startDriving(id)
    }

    /// `awaitingInput(noTestCommand | testTimedOut) -> review`.
    /// Complexity: O(1) time, O(1) space
    func skipTests(_ id: UUID) throws(WorkflowError) {
        let task = try lookup(id)
        guard task.state == .awaitingInput, task.waitReason?.allowsSkippingTests == true else {
            throw .illegalTransition(from: task.state, to: .review)
        }
        if case .testEntryModified = task.waitReason { acceptCurrentTestEntryPoint(id) }
        publish(try TaskTransitions.move(task, to: .review, fixLoopCap: effectiveSettings(for: id).fixLoopCap))
        startDriving(id)
    }

    /// Idempotent. Cancels the running stage (Claude stream and test run) and publishes `cancelled` once.
    /// Complexity: O(1) time, O(1) space
    func cancel(_ id: UUID) {
        drivers[id]?.cancel()
        drivers[id] = nil
        apply(id, to: .cancelled)
    }

    func task(_ id: UUID) -> WorkflowTask? { tasks[id] }

    /// Replaces the settings used by tasks submitted after this call. Running and already queued tasks keep theirs.
    /// Complexity: O(1) time, O(1) space
    func update(settings: EngineSettings) {
        self.settings = settings
    }

    /// The copy a task was submitted with; falls back to the current settings for an unknown id.
    /// Complexity: O(1) time, O(1) space
    func effectiveSettings(for id: UUID) -> EngineSettings {
        taskSettings[id] ?? settings
    }

    // MARK: - State changes

    func lookup(_ id: UUID) throws(WorkflowError) -> WorkflowTask {
        guard let task = tasks[id] else { throw .unknownTask(id) }
        return task
    }

    func publish(_ task: WorkflowTask) {
        tasks[task.id] = task
        continuation.yield(task)
    }

    /// Publishes an edited copy without changing the state.
    func update(_ id: UUID, _ edit: (WorkflowTask) -> WorkflowTask) {
        guard let task = tasks[id] else { return }
        publish(edit(task))
    }

    /// Moves a non-terminal task through the guarded table; `edit` runs first. Returns false when not applied.
    @discardableResult
    func apply(_ id: UUID, to state: TaskState, _ edit: (WorkflowTask) -> WorkflowTask = { $0 }) -> Bool {
        guard let task = tasks[id], !task.state.isTerminal else { return false }
        do {
            publish(try TaskTransitions.move(edit(task), to: state, fixLoopCap: effectiveSettings(for: id).fixLoopCap))
            return true
        } catch {
            AppLog.workflow.error("illegal engine transition \(task.state.rawValue) -> \(state.rawValue)")
            return false
        }
    }

    func fail(_ id: UUID, _ reason: FailureReason) {
        apply(id, to: .failed) { $0.with(failure: reason) }
    }

    func park(_ id: UUID, _ reason: WaitReason) {
        apply(id, to: .awaitingInput) { $0.with(waiting: reason, resume: nil) }
    }

    /// True while the task is still in `state` and nobody cancelled the driver.
    func isCurrent(_ id: UUID, _ state: TaskState) -> Bool {
        !Task.isCancelled && tasks[id]?.state == state
    }

    // MARK: - Driver

    private func startDriving(_ id: UUID) {
        guard drivers[id] == nil else { return }
        drivers[id] = Task { await self.drive(id) }
    }

    /// Runs handlers until the task parks (approval, input) or ends. A handler that leaves the state unchanged
    /// (cancelled mid-stage) ends the loop.
    /// Complexity: O(stages run) time, O(1) space
    private func drive(_ id: UUID) async {
        while !Task.isCancelled, let state = tasks[id]?.state {
            switch state {
            case .queued: await prepare(id)
            case .plan: await runPlan(id)
            case .code: await runCode(id)
            case .test: await runTests(id)
            case .fix: await runFix(id)
            case .review: await runReview(id)
            case .awaitingApproval, .awaitingInput, .done, .failed, .cancelled:
                drivers[id] = nil
                return
            }
            if tasks[id]?.state == state { break }
        }
        if !Task.isCancelled { drivers[id] = nil }
    }
}
