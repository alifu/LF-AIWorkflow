//
//  WorkflowEngine.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Drives tasks through `queued -> plan -> approval -> code -> (test <-> fix)* -> review -> done`.
/// All state lives in this actor; every change is a new immutable `WorkflowTask` published to every `makeUpdates()` stream.
/// One driver `Task` per running task; `cancel` cancels it, which ends the Claude stream (killing the child)
/// and the test run. Stage handlers live in `WorkflowEngine+Stages.swift`.
actor WorkflowEngine {
    /// Live update subscribers; each view-model start gets its own stream (TD-115).
    nonisolated let hub = UpdateHub()

    let deps: EngineDependencies
    /// All blocking file I/O: debounced task saves, plan/review files, existence checks (TD-123, TD-108).
    let writer: TaskStoreWriter
    /// Settings for tasks submitted from now on. Tasks already submitted keep their copy in `taskSettings`.
    private(set) var settings: EngineSettings
    /// Snapshot taken at submit; every stage of that task reads it, so a Settings change never reaches a running task.
    /// Tasks that skip Plan (`TaskDraft.startAtCode`); only read while the task is `queued`.
    var startAtCode: Set<UUID> = []
    /// Findings waiting for the next Fix stage (`sendToFix`); cleared once that stage ran.
    var findingsForFix: [UUID: [Finding]] = [:]
    var taskSettings: [UUID: EngineSettings] = [:]
    var tasks: [UUID: WorkflowTask] = [:]
    var budgets: [UUID: TokenBudget] = [:]
    var testCommands: [UUID: TestCommand] = [:]
    /// Fingerprint of each task's test entry point as the Code stage started (see `TestEntryGuard`).
    var entryFingerprints: [UUID: String] = [:]
    /// Hashes of plan documents already sent; honoured only when the stage resumes the Claude session (TD-027).
    var sentDocumentHashes: [UUID: Set<UInt64>] = [:]
    private var drivers: [UUID: Task<Void, Never>] = [:]

    init(dependencies: EngineDependencies, settings: EngineSettings) {
        deps = dependencies
        writer = TaskStoreWriter(store: dependencies.store, debounce: dependencies.persistDebounce)
        self.settings = settings
    }

    deinit {
        hub.finishAll()
        for driver in drivers.values { driver.cancel() }
    }

    // MARK: - Public API

    /// A fresh update stream that starts with every known task (oldest first), then follows live changes.
    /// Complexity: O(n log n) time, O(n) space (n = known tasks)
    func makeUpdates() -> AsyncStream<WorkflowTask> {
        hub.subscribe(replaying: tasks.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) })
    }

    private func emit(_ task: WorkflowTask) { hub.yield(task) }

    /// Complexity: O(1) time, O(1) space
    func submit(_ draft: TaskDraft) -> UUID {
        let task = WorkflowTask(
            id: UUID(), title: draft.title, slug: WorktreeManager.slug(for: draft.title), prompt: draft.prompt,
            projectRoot: draft.projectRoot, documents: draft.documents, skillDirs: draft.skillDirs, state: .queued,
            resumeState: nil, waitReason: nil, failure: nil, worktree: nil, sessionId: nil, planFile: nil,
            fixAttempts: 0, usageByStage: [:], lastErrors: nil, testCommandDisplay: nil, reviewFile: nil,
            createdAt: Date())
        taskSettings[task.id] = draft.useWorktree.map { settings.with(useWorktree: $0) } ?? settings
        if draft.startAtCode { startAtCode.insert(task.id) }
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

    /// `failed -> the stage it failed in`; clears the failure and starts driving again (TD-043).
    /// Complexity: O(1) time, O(1) space
    func retry(_ id: UUID) throws(WorkflowError) {
        let task = try lookup(id)
        guard task.state == .failed else { throw .illegalTransition(from: task.state, to: task.retryState ?? .queued) }
        taskSettings[id] = settings
        publish(try TaskTransitions.move(task, to: task.retryState ?? .queued, fixLoopCap: settings.fixLoopCap))
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
    func cancel(_ id: UUID) async {
        drivers[id]?.cancel()
        drivers[id] = nil
        let state = tasks[id]?.state
        if apply(id, to: .cancelled), let state { await log("Cancelled", id, state) }
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

    /// Complexity: O(1) time, O(1) space
    func lookup(_ id: UUID) throws(WorkflowError) -> WorkflowTask {
        guard let task = tasks[id] else { throw .unknownTask(id) }
        return task
    }

    /// Complexity: O(1) time, O(1) space (plus the mailbox hand-off and the yield)
    func publish(_ task: WorkflowTask) {
        tasks[task.id] = task
        if task.state.isTerminal { taskSettings[task.id] = nil }
        persist()
        emit(task)
    }

    /// Loads persisted tasks once at launch (call before the first `submit`). Tasks that were mid-stage when
    /// the app quit come back parked as `awaitingInput` (resume state = the interrupted stage); a task that never
    /// left `queued` comes back failed. Nothing is driven: the user resumes. Ids already known are skipped.
    /// Returns the number of tasks restored. Per-task budget raises and cached test commands are not persisted.
    /// Complexity: O(n log n) time, O(n) space (n = persisted tasks)
    @discardableResult
    func restore() async -> Int {
        guard deps.store != nil else { return 0 }
        let stored = await writer.load()
        let loaded = TaskRestore.interrupted(stored, now: Date()).filter { tasks[$0.id] == nil }
        for task in loaded.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }) {
            tasks[task.id] = task
            emit(task)
        }
        persist()
        return loaded.count
    }

    /// Hands the latest snapshot to the writer, which coalesces and writes it after the debounce.
    /// Complexity: O(n) time, O(n) space (n = tasks, copied into the mailbox)
    private func persist() {
        writer.schedule(Array(tasks.values))
    }

    /// Writes the latest task state to disk now. Call on app terminate so the last state is not lost.
    /// Complexity: O(n log n) time, O(n) space (n = tasks)
    func stop() async {
        await writer.flush()
    }

    /// Publishes an edited copy without changing the state.
    /// Complexity: O(1) time, O(1) space (plus the publish)
    func update(_ id: UUID, _ edit: (WorkflowTask) -> WorkflowTask) {
        guard let task = tasks[id] else { return }
        publish(edit(task))
    }

    /// Moves a non-terminal task through the guarded table; `edit` runs first. Returns false when not applied.
    /// Complexity: O(1) time, O(1) space
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

    /// Fails the task and logs the reason (TD-037).
    /// Complexity: O(log line) time, O(1) space
    func fail(_ id: UUID, _ reason: FailureReason) async {
        let state = tasks[id]?.state
        // A failure raised while parked retries into the parked stage, not `awaitingInput` or `queued` (TD-132).
        let retryState = state == .awaitingInput ? tasks[id]?.resumeState : state
        guard apply(id, to: .failed, { $0.with(failure: reason).with(retryState: retryState) }), let state else { return }
        await log(TaskText.failureText(reason), id, state)
    }

    /// Parks the task for input and logs why (TD-037).
    /// Complexity: O(log line) time, O(1) space
    func park(_ id: UUID, _ reason: WaitReason) async {
        let state = tasks[id]?.state
        guard apply(id, to: .awaitingInput, { $0.with(waiting: reason, resume: nil) }), let state else { return }
        await log(TaskText.waitText(reason), id, state)
    }

    /// True while the task is still in `state` and nobody cancelled the driver.
    /// Complexity: O(1) time, O(1) space
    func isCurrent(_ id: UUID, _ state: TaskState) -> Bool {
        !Task.isCancelled && tasks[id]?.state == state
    }

    // MARK: - Driver

    /// Complexity: O(1) time, O(1) space
    func startDriving(_ id: UUID) {
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
