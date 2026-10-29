//
//  TaskBoard.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct CollapsedSummary: Sendable, Equatable {
    let activeCount: Int
    let leadStep: PipelineStep?
    let attentionCount: Int

    /// "2 tasks running, Code stage" / "No active tasks", plus ", N need attention" when relevant.
    var accessibilityLabel: String {
        var parts: [String] = []
        if activeCount == 0 {
            parts.append("No active tasks")
        } else {
            parts.append("\(activeCount) \(activeCount == 1 ? "task" : "tasks") running")
            if let leadStep { parts.append("\(leadStep.displayName) stage") }
        }
        if attentionCount > 0 { parts.append("\(attentionCount) \(attentionCount == 1 ? "needs" : "need") attention") }
        return parts.joined(separator: ", ")
    }
}

nonisolated struct PeekMessage: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case planReady, failed, done, needsInput
        /// Plain notice not tied to a task (for example "Saved to inbox (3)").
        case info
    }
    let taskID: UUID
    let text: String
    let kind: Kind
    /// Increases with every message so an identical repeat still changes the value.
    let sequence: Int

    /// `taskID` of notices that are not about a task.
    static let noTask = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// Pure state behind the view model: latest snapshot per task, finish times, hidden rows, peek dedupe.
nonisolated struct TaskBoard: Sendable {
    var showAlerts = true

    private var tasks: [UUID: WorkflowTask] = [:]
    private var finishedAt: [UUID: Date] = [:]
    private var hidden: Set<UUID> = []
    private var lastState: [UUID: TaskState] = [:]
    private var peekCount = 0
    /// Done tasks whose saved review must be read before their done peek can say how many findings it has.
    private var awaitingReview: Set<UUID> = []

    /// Records a snapshot; returns a peek message when the task just ENTERED an attention state. A task that just
    /// finished with a saved review returns nil instead: call `awaitsReview` and then `reviewLoaded` (TD-049).
    /// Complexity: O(1) time, O(1) space
    mutating func apply(_ task: WorkflowTask, now: Date) -> PeekMessage? {
        let previous = lastState[task.id]
        tasks[task.id] = task
        lastState[task.id] = task.state
        if task.state.isTerminal, finishedAt[task.id] == nil { finishedAt[task.id] = task.finishedAt ?? now }
        guard showAlerts, previous != task.state, let kind = Self.peekKind(task.state) else { return nil }
        if kind == .done, task.reviewFile != nil {
            awaitingReview.insert(task.id)
            return nil
        }
        peekCount += 1
        return PeekMessage(taskID: task.id, text: "\(task.title): \(Self.peekText(task, kind))", kind: kind, sequence: peekCount)
    }

    /// True between a task's done transition (with a saved review) and its `reviewLoaded` call.
    /// Complexity: O(1) time, O(1) space
    func awaitsReview(_ id: UUID) -> Bool { awaitingReview.contains(id) }

    /// Completes a deferred done peek. `findings` is nil when the review could not be read; the peek then stays plain "done".
    /// Complexity: O(1) time, O(1) space
    mutating func reviewLoaded(for id: UUID, findings: Int?) -> PeekMessage? {
        guard awaitingReview.remove(id) != nil, let task = tasks[id] else { return nil }
        let outcome = findings.map { "done, \($0) \($0 == 1 ? "finding" : "findings")" } ?? "done"
        peekCount += 1
        return PeekMessage(taskID: id, text: "\(task.title): \(outcome)", kind: .done, sequence: peekCount)
    }

    /// A plain notice that belongs to no task; shares the sequence counter so repeats still differ.
    /// Complexity: O(1) time, O(1) space
    mutating func notice(_ text: String) -> PeekMessage {
        peekCount += 1
        return PeekMessage(taskID: PeekMessage.noTask, text: text, kind: .info, sequence: peekCount)
    }

    /// Hides done, failed and cancelled rows (the tasks stay known).
    mutating func clearDone() {
        hidden.formUnion(tasks.values.filter { $0.state.isTerminal }.map(\.id))
    }

    func task(_ id: UUID) -> WorkflowTask? { tasks[id] }

    /// Attention first, then newest. Hidden rows are left out.
    /// Complexity: O(n log n) time, O(n) space
    func rows(now: Date, fixLoopCap: Int) -> [TaskRowModel] {
        tasks.values
            .filter { !hidden.contains($0.id) }
            .map { TaskRowModel($0, now: finishedAt[$0.id] ?? now, fixLoopCap: fixLoopCap) }
            .sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Counts running tasks only (queued and parked ones are not "active").
    /// Complexity: O(n) time, O(1) space
    func summary() -> CollapsedSummary {
        let running = tasks.values.filter { TaskRowModel.runningStates.contains($0.state) }
        let lead = running.max { $0.createdAt < $1.createdAt }
        let attention = tasks.values.filter { TaskRowModel.attentionStates.contains($0.state) && !hidden.contains($0.id) }
        return CollapsedSummary(activeCount: running.count, leadStep: lead.flatMap { PipelineStep(state: $0.state) },
                                attentionCount: attention.count)
    }

    /// Billable tokens of tasks created on the same calendar day as `now`.
    /// Complexity: O(n) time, O(1) space
    func todayTokens(now: Date, calendar: Calendar) -> Int {
        tasks.values.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(0) { $0 + $1.totalUsage.billableTotal }
    }

    // MARK: - Helpers

    private static func peekKind(_ state: TaskState) -> PeekMessage.Kind? {
        switch state {
        case .awaitingApproval: .planReady
        case .failed: .failed
        case .done: .done
        case .awaitingInput: .needsInput
        default: nil
        }
    }

    private static func peekText(_ task: WorkflowTask, _ kind: PeekMessage.Kind) -> String {
        switch kind {
        case .planReady: "plan ready, approve?"
        case .failed: "failed"
        case .done: "done"
        case .needsInput: TaskText.waitText(task.waitReason)
        case .info: ""
        }
    }
}
