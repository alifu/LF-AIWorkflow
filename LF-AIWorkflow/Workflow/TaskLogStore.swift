//
//  TaskLogStore.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct TaskLogLine: Sendable, Equatable, Identifiable {
    let id: Int
    let stage: TaskState
    let text: String
}

/// Where the engine writes human-readable activity. Optional in `EngineDependencies`.
nonisolated protocol TaskLogging: Sendable {
    func append(_ text: String, stage: TaskState, to id: UUID) async
}

/// Bounded per-task activity log (ANSI stripped). Feeds the Terminal tab.
actor TaskLogStore: TaskLogging {
    nonisolated let changes: AsyncStream<UUID>
    private let continuation: AsyncStream<UUID>.Continuation
    private let capacity: Int
    private var logs: [UUID: [TaskLogLine]] = [:]
    private var nextId = 0

    init(capacityPerTask: Int = 500) {
        capacity = max(1, capacityPerTask)
        (changes, continuation) = AsyncStream.makeStream(of: UUID.self, bufferingPolicy: .bufferingNewest(256))
    }

    deinit { continuation.finish() }

    /// Strips ANSI, splits into lines, drops blank ones, evicts the oldest beyond capacity.
    /// Complexity: O(len + capacity) time, O(capacity) space
    func append(_ text: String, stage: TaskState, to id: UUID) {
        let clean = AnsiStripper.strip(text)
        let pieces = clean.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pieces.isEmpty else { return }
        var current = logs[id, default: []]
        for piece in pieces {
            current.append(TaskLogLine(id: nextId, stage: stage, text: piece))
            nextId += 1
        }
        if current.count > capacity { current.removeFirst(current.count - capacity) }
        logs[id] = current
        continuation.yield(id)
    }

    /// Complexity: O(1) time, O(1) space (copy-on-write)
    func lines(for id: UUID) -> [TaskLogLine] { logs[id] ?? [] }
}
