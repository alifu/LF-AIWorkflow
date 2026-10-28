//
//  ResearchViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

/// One research row in the task list.
nonisolated struct ResearchRowModel: Sendable, Equatable, Identifiable {
    let id: UUID
    let question: String
    let state: ResearchState
    let chips: [ChipDisplay]
    let createdAt: Date
    let tokensUsed: Int
    let needsAttention: Bool
    let isFinished: Bool
}

nonisolated enum ResearchURLError: Error, Sendable, Equatable {
    case invalid
    case blocked(String)
}

/// What the view model needs from the pipeline; lets tests record commands.
protocol ResearchControlling: Sendable {
    func submit(_ draft: ResearchDraft) async -> UUID
    func send(_ id: UUID, excluded: Set<Int>) async
    func cancel(_ id: UUID) async
    func followUp(_ id: UUID, question: String) async
}

extension ResearchPipeline: ResearchControlling {}

/// What the view model needs from the research inbox.
protocol ResearchInboxing: Sendable {
    func items() async throws -> [InboxItem]
    func drain() async throws -> [InboxItem]
}

extension ResearchInbox: ResearchInboxing {}

/// Bridge between the research pipeline actor and the views. The sole consumer of `pipeline.updates`;
/// publishes at most one UI update per coalescing window, like `WorkflowViewModel`.
@MainActor @Observable
final class ResearchViewModel {
    private(set) var rows: [ResearchRowModel] = []
    private(set) var safariState: SafariPermissionState = .notDetermined
    private(set) var inboxCount = 0
    /// Mascot pose for the research work in flight; nil when nothing is running.
    private(set) var pose: MascotPose?

    /// Token total of the newest task waiting at the preview (live estimate after cleaning); nil when none.
    private(set) var estimatedTokens: Int?

    @ObservationIgnored private let controller: (any ResearchControlling)?
    @ObservationIgnored private let inbox: (any ResearchInboxing)?
    @ObservationIgnored private let hostPolicy: HostPolicy
    @ObservationIgnored private var autoSend: Set<UUID> = []
    @ObservationIgnored private var commandTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let updates: AsyncStream<ResearchTask>
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let coalesceInterval: Duration
    @ObservationIgnored private var tasks: [UUID: ResearchTask] = [:]
    @ObservationIgnored private var reportModels: [UUID: ResearchReportViewModel] = [:]
    @ObservationIgnored private var createdAt: [UUID: Date] = [:]
    @ObservationIgnored private var reachedIndex: [UUID: Int] = [:]
    @ObservationIgnored private var extractRan: Set<UUID> = []
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingUpdate = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(updates: AsyncStream<ResearchTask>, clock: any Clock<Duration> = ContinuousClock(),
         now: @escaping @Sendable () -> Date = { Date() }, coalesceInterval: Duration = .milliseconds(100),
         controller: (any ResearchControlling)? = nil, inbox: (any ResearchInboxing)? = nil,
         hostPolicy: HostPolicy = .standard) {
        self.controller = controller
        self.inbox = inbox
        self.hostPolicy = hostPolicy
        self.updates = updates
        self.clock = clock
        self.now = now
        self.coalesceInterval = coalesceInterval
    }

    // MARK: - Lifecycle

    /// Starts consuming the pipeline stream. Idempotent.
    func start() {
        guard updatesTask == nil else { return }
        let updates = updates
        updatesTask = Task { [weak self] in
            for await task in updates {
                guard let self else { return }
                self.receive(task)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        windowTask?.cancel()
        updatesTask = nil
        windowTask = nil
    }


    func task(_ id: UUID) -> ResearchTask? { tasks[id] }

    /// One detail model per task, kept so preview exclusions survive redraws; its task snapshot is refreshed on each call.
    func reportModel(for id: UUID) -> ResearchReportViewModel? {
        guard let task = tasks[id], let controller else { return nil }
        if let existing = reportModels[id] { existing.update(task); return existing }
        let model = ResearchReportViewModel(task: task, controller: controller)
        reportModels[id] = model
        return model
    }

    func setSafariState(_ state: SafariPermissionState) { safariState = state }
    func setInboxCount(_ count: Int) { inboxCount = count }

    // MARK: - Commands

    /// Queues a research task; it stops at the preview unless `autoSend` and nothing is flagged.
    /// Inbox pages in the draft are consumed (the inbox is emptied) once the task is queued.
    /// Complexity: O(1) time to enqueue, O(1) space
    @discardableResult
    func preview(_ draft: ResearchDraft, autoSend: Bool = false) async -> UUID? {
        guard let controller else { return nil }
        let id = await controller.submit(draft)
        if autoSend {
            self.autoSend.insert(id)
            if let known = tasks[id] { evaluateAutoSend(known) }
        }
        if !draft.inboxPages.isEmpty, let inbox {
            _ = try? await inbox.drain()
            inboxCount = 0
        }
        return id
    }

    /// Sends the non-excluded sources (1-based preview numbers) to Claude.
    func send(_ id: UUID, excluded: Set<Int>) async { await controller?.send(id, excluded: excluded) }

    func cancel(_ id: UUID) async {
        autoSend.remove(id)
        await controller?.cancel(id)
    }

    /// Validates a typed URL: canonical http(s) form, then the SSRF host policy.
    /// Complexity: O(n log n) time (n = URL length), O(n) space
    func addURL(_ text: String) -> Result<URL, ResearchURLError> {
        guard let url = URLNormalizer.normalize(text) else { return .failure(.invalid) }
        if case .blocked(let reason) = hostPolicy.check(url) { return .failure(.blocked(reason)) }
        return .success(url)
    }

    /// Reads the inbox without emptying it; the count follows.
    func useInbox() async -> [CapturedPage] {
        guard let inbox, let items = try? await inbox.items() else { return [] }
        inboxCount = items.count
        return items.map(\.page)
    }

    /// Waits for fire-and-forget commands (auto-send); tests and shutdown use it.
    func settleCommands() async {
        let pending = commandTasks
        commandTasks = []
        for task in pending { await task.value }
    }

    private func evaluateAutoSend(_ task: ResearchTask) {
        guard task.state == .awaitingPreview, autoSend.contains(task.id), let controller,
              let preview = task.preview else { return }
        autoSend.remove(task.id)
        // `.removed` is informational (boilerplate stripped); only empty or duplicate sources need a human look.
        guard preview.rows.allSatisfy({ $0.flags.isDisjoint(with: [.looksEmpty, .duplicate]) }) else { return }
        let id = task.id
        commandTasks.append(Task { await controller.send(id, excluded: []) })
    }

    // MARK: - Updates

    /// Applies one pipeline snapshot; the first after a quiet period publishes at once, the rest fold into the window.
    /// Complexity: O(n log n) time per publication (n = tasks), O(n) space
    func receive(_ task: ResearchTask) {
        track(task)
        if windowTask == nil {
            publish()
            openWindow()
        } else {
            hasPendingUpdate = true
        }
    }

    /// Publishes any pending update now (used when the window is not worth waiting for).
    func flush() {
        windowTask?.cancel()
        windowTask = nil
        hasPendingUpdate = false
        publish()
    }

    private func track(_ task: ResearchTask) {
        tasks[task.id] = task
        evaluateAutoSend(task)
        if createdAt[task.id] == nil { createdAt[task.id] = now() }
        if let index = ResearchStep.index(for: task.state) { reachedIndex[task.id] = index }
        if task.state == .extract { extractRan.insert(task.id) }
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
        let built = tasks.values.map(row)
        rows = built.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
        pose = Self.pose(for: built)
        estimatedTokens = tasks.values.filter { $0.state == .awaitingPreview && $0.preview != nil }
            .max { (createdAt[$0.id] ?? .distantPast) < (createdAt[$1.id] ?? .distantPast) }?.preview?.totalTokens
    }

    private func row(_ task: ResearchTask) -> ResearchRowModel {
        let chips = ResearchStep.chips(state: task.state, reachedIndex: reachedIndex[task.id] ?? 0,
                                       extractRan: extractRan.contains(task.id))
        let finished = [ResearchState.done, .failed, .cancelled].contains(task.state)
        return ResearchRowModel(id: task.id, question: task.question, state: task.state, chips: chips,
                                createdAt: createdAt[task.id] ?? now(), tokensUsed: task.tokensUsed,
                                needsAttention: task.state == .awaitingInput || task.state == .failed,
                                isFinished: finished)
    }

    /// Attention wins, then reading (capture, analyze), then plain work.
    /// Complexity: O(n) time, O(1) space
    private static func pose(for rows: [ResearchRowModel]) -> MascotPose? {
        if rows.contains(where: { $0.state == .awaitingInput }) { return .attention }
        if rows.contains(where: { $0.state == .capture || $0.state == .analyze }) { return .reading }
        if rows.contains(where: { !$0.isFinished && $0.state != .queued && $0.state != .awaitingPreview }) { return .typing }
        return nil
    }
}
