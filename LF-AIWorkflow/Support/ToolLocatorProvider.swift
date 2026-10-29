//
//  ToolLocatorProvider.swift
//  LF-AIWorkflow
//

import Foundation

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
