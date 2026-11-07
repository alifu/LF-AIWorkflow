//
//  UpdateHub.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Fans engine snapshots out to the live subscribers. Nothing is buffered without a subscriber, and a subscriber that
/// stops iterating is dropped when its stream terminates (TD-115).
nonisolated final class UpdateHub: Sendable {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<WorkflowTask>.Continuation]())

    var subscriberCount: Int { continuations.withLock { $0.count } }

    /// Complexity: O(1) time, O(1) space
    func subscribe(replaying snapshot: [WorkflowTask] = []) -> AsyncStream<WorkflowTask> {
        let (stream, continuation) = AsyncStream.makeStream(of: WorkflowTask.self, bufferingPolicy: .unbounded)
        for task in snapshot { continuation.yield(task) }
        let key = UUID()
        continuations.withLock { $0[key] = continuation }
        continuation.onTermination = { [continuations] _ in continuations.withLock { $0[key] = nil } }
        return stream
    }

    /// Complexity: O(s) time, O(1) space (s = subscribers)
    func yield(_ task: WorkflowTask) {
        let current = continuations.withLock { Array($0.values) }
        for continuation in current { continuation.yield(task) }
    }

    func finishAll() {
        let current = continuations.withLock { Array($0.values) }
        for continuation in current { continuation.finish() }
    }
}
