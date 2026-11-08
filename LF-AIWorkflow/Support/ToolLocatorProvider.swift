//
//  ToolLocatorProvider.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Lock-backed copy of the Settings tool paths, readable from any context without a MainActor hop.
/// Complexity: O(1) time per write, O(k) time per read (k = overrides, copied out), O(k) space
nonisolated final class ToolPathStore: Sendable {
    private let paths: OSAllocatedUnfairLock<[Tool: String]>

    init(_ initial: [Tool: String] = [:]) { paths = OSAllocatedUnfairLock(initialState: initial) }

    /// Complexity: O(k) time (replaces the map), O(k) space
    func set(_ newPaths: [Tool: String]) { paths.withLock { $0 = newPaths } }

    /// Complexity: O(k) time (copies the map), O(k) space
    var current: [Tool: String] { paths.withLock { $0 } }
}

/// Hands out the current `ToolLocator` on every call, so a changed CLI path applies to the next task without a relaunch.
nonisolated struct ToolLocatorProvider: Sendable {
    private let source: @Sendable () async -> ToolLocator

    init(_ source: @escaping @Sendable () async -> ToolLocator) { self.source = source }

    /// A provider that always returns the same locator.
    init(fixed locator: ToolLocator) { self.source = { locator } }

    /// Complexity: O(1) time beyond the source, O(1) space
    func current() async -> ToolLocator { await source() }
}

/// Runs each Claude stage with the executable located at that moment (tool path overrides re-read per run).
/// A missing or invalid tool finishes the stream with the locator's error.
nonisolated struct LiveClaudeRunner: ClaudeStageRunning, ResearchClaudeRunning {
    let locators: ToolLocatorProvider
    let baseEnvironment: [String: String]
    let searchPath: [String]

    /// Complexity: O(d) time per run over PATH entries, O(1) space beyond the event buffer
    func run(_ request: StageRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        forward { $0.run(request) }
    }

    /// Complexity: O(d) time per run over PATH entries, O(1) space beyond the event buffer
    func run(_ request: ResearchRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        forward { $0.run(request) }
    }

    private func forward(
        _ start: @escaping @Sendable (ClaudeStageRunner) -> AsyncThrowingStream<StageRunEvent, Error>
    ) -> AsyncThrowingStream<StageRunEvent, Error> {
        let (locators, env, path) = (locators, baseEnvironment, searchPath)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let executable = try await locators.current().locate(.claude)
                    let runner = ClaudeStageRunner(executable: executable, baseEnvironment: env, searchPath: path)
                    for try await event in start(runner) { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
