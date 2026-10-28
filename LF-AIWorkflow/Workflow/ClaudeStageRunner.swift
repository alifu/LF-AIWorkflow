//
//  ClaudeStageRunner.swift
//  LF-AIWorkflow
//

import Foundation

/// Runs one Claude stage through `ClaudeSession` and maps its events to `StageRunEvent`.
/// The stream ends with exactly one `.finished`; a consumer that stops iterating kills the child.
nonisolated struct ClaudeStageRunner: ClaudeStageRunning {
    private static let activityCap = 200
    private static let diagnosticCap = 500

    private let executable: URL
    private let baseEnvironment: [String: String]
    private let searchPath: [String]

    init(executable: URL, baseEnvironment: [String: String], searchPath: [String]) {
        self.executable = executable
        self.baseEnvironment = baseEnvironment
        self.searchPath = searchPath
    }

    /// Builds the invocation first (an invalid tool rule finishes the stream with the error, nothing is spawned).
    /// Complexity: O(e) time over the child's events, O(1) space beyond the event buffer
    func run(_ request: StageRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        let (executable, baseEnvironment, searchPath) = (self.executable, self.baseEnvironment, self.searchPath)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let invocation = try ClaudeCommandBuilder.invocation(
                        executable: executable, config: request.config, sessionId: request.sessionId,
                        addDirs: request.addDirs, workingDirectory: request.workingDirectory, prompt: request.prompt,
                        baseEnvironment: baseEnvironment, searchPath: searchPath)
                    let session = try ClaudeSession()
                    try await session.start(invocation)
                    await Self.pump(session, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Mapping

    private static func pump(_ session: ClaudeSession, into continuation: AsyncThrowingStream<StageRunEvent, Error>.Continuation) async {
        var finished = false
        var diagnostic: String?
        await withTaskCancellationHandler {
            for await event in session.events {
                switch event {
                case .assistant(let message):
                    for activity in activities(of: message) { continuation.yield(.activity(activity)) }
                    if message.usage != nil { continuation.yield(.usage(await session.usage)) }
                case .result(let result):
                    finished = true
                    let trackedId = await session.sessionId
                    continuation.yield(.finished(StageRunOutcome(
                        text: result.text, sessionId: result.sessionId ?? trackedId, usage: result.usage,
                        isError: result.isError, permissionDenials: result.permissionDenials, exitStatus: nil)))
                case .unparsed(let line):
                    diagnostic = String(line.prefix(diagnosticCap))
                case .exited(let status):
                    guard !finished else { break }
                    finished = true
                    continuation.yield(.finished(StageRunOutcome(
                        text: diagnostic, sessionId: await session.sessionId, usage: await session.usage,
                        isError: true, permissionDenials: [], exitStatus: status)))
                case .initialized, .toolResult, .unknown:
                    break
                }
            }
        } onCancel: {
            Task { await session.cancel() }
        }
    }

    /// One line per text block and per tool use, each capped.
    private static func activities(of message: AssistantMessage) -> [String] {
        let texts = message.texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let tools = message.toolUses.map { $0.inputSummary.isEmpty ? $0.name : "\($0.name): \($0.inputSummary)" }
        return (texts + tools).map { String($0.prefix(activityCap)) }
    }
}
