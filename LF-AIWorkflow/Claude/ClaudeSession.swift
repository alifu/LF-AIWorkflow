//
//  ClaudeSession.swift
//  LF-AIWorkflow
//

import Foundation
import os

nonisolated enum ClaudeSessionError: Error, Sendable, Equatable {
    case alreadyStarted
    case cancelled
    case spawnFailed(Int32)
}

/// One `claude -p` run: spawns the child, frames and decodes its stream-JSON output into `events`.
actor ClaudeSession {
    /// Single consumer: the first access hands out the stream, later accesses get an already-finished one.
    /// The session keeps no reference to it, so when the consumer drops the stream and its iterator (for example
    /// by leaving the loop) `onTermination` fires and the child is killed.
    nonisolated var events: AsyncStream<ClaudeEvent> {
        eventStream.withLock { stream in
            defer { stream = nil }
            return stream ?? AsyncStream { $0.finish() }
        }
    }
    private(set) var sessionId: String?
    private(set) var exitStatus: Int32?
    /// Running total of assistant usage (latest usage per message id); replaced by the result's total.
    private(set) var usage: TokenUsage = .zero

    private nonisolated let eventStream: OSAllocatedUnfairLock<AsyncStream<ClaudeEvent>?>
    private let continuation: AsyncStream<ClaudeEvent>.Continuation
    private let ring: RingBuffer
    private let framer: NDJSONFramer
    private var process: PTYProcess?
    private var started = false
    private var cancelled = false
    /// Assistant lines repeat a message id with cumulative usage; the per-field max is kept per id.
    private var usageByMessageId: [String: TokenUsage] = [:]
    private var anonymousUsage: TokenUsage = .zero

    /// Complexity: O(C) time, O(C) space (C = terminal capacity)
    init(terminalCapacity: Int = 256 * 1024) throws {
        ring = try RingBuffer(capacity: terminalCapacity)
        framer = try NDJSONFramer()
        let (stream, continuation) = AsyncStream.makeStream(of: ClaudeEvent.self, bufferingPolicy: .unbounded)
        self.continuation = continuation
        eventStream = OSAllocatedUnfairLock(initialState: stream)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancel() }
        }
    }

    var processID: Int32? { process?.pid }

    /// Starts the run; once per instance. The child never sees variables in `ClaudeCommandBuilder.droppedEnvironmentKeys`.
    /// Throws `.cancelled` (without spawning) if `cancel()` came first.
    /// Complexity: O(argc + envc) time, O(argc + envc) space
    func start(_ invocation: ProcessInvocation) async throws(ClaudeSessionError) {
        guard !started else { throw .alreadyStarted }
        started = true
        guard !cancelled else {
            continuation.finish()
            throw .cancelled
        }
        let sanitized = ProcessInvocation(
            executable: invocation.executable, arguments: invocation.arguments,
            environment: ClaudeCommandBuilder.sanitized(invocation.environment),
            workingDirectory: invocation.workingDirectory, stdin: invocation.stdin)
        let spawned: PTYProcess
        do {
            spawned = try await PTYProcess.spawnOffPool(sanitized)
        } catch {
            continuation.finish()
            guard case .posix(let code) = error else { throw .spawnFailed(EIO) }
            throw .spawnFailed(code)
        }
        // `cancel()` may have run while the spawn was suspended; it could not see this child yet.
        guard !cancelled else {
            spawned.terminate()
            continuation.finish()
            throw .cancelled
        }
        process = spawned
        AppLog.claude.info("claude spawned pid=\(spawned.pid) cwd=\(sanitized.workingDirectory.path, privacy: .private)")
        Task { [self] in
            for await out in spawned.output { handle(out) }
        }
    }

    /// Kills the child's process group; the stream ends with `.exited`. Safe to call repeatedly.
    /// Complexity: O(1) time, O(1) space
    func cancel() {
        cancelled = true
        process?.terminate()
    }

    /// Raw pty bytes (last `terminalCapacity`) for the Terminal tab.
    /// Complexity: O(C) time, O(C) space
    func terminalSnapshot() -> Data { ring.snapshot() }

    // MARK: - Output handling

    /// Complexity: O(n) time, O(n) space (n = bytes in this output chunk)
    private func handle(_ out: PTYProcess.Output) {
        switch out {
        case .data(let data):
            ring.write(data)
            do {
                emit(lines: try framer.feed(data))
            } catch {
                AppLog.claude.error("framer feed failed: \(String(describing: error))")
            }
        case .exited(let status):
            if let rest = try? framer.finish() { emit(lines: rest) }
            exitStatus = status
            process = nil
            AppLog.claude.info("claude exited status=\(status)")
            continuation.yield(.exited(status: status))
            continuation.finish()
        }
    }

    /// Complexity: O(n) time, O(n) space (n = total bytes in `lines`)
    private func emit(lines: [Data]) {
        for line in lines {
            for event in ClaudeEventDecoder.decode(line) {
                track(event)
                continuation.yield(event)
            }
        }
    }

    /// Complexity: O(m) time, O(1) space (m = distinct assistant message ids seen)
    private func track(_ event: ClaudeEvent) {
        switch event {
        case .initialized(let info): sessionId = info.sessionId
        case .assistant(let message):
            guard let messageUsage = message.usage else { return }
            if let id = message.messageId {
                usageByMessageId[id] = usageByMessageId[id].map { $0.maxing(messageUsage) } ?? messageUsage
            } else {
                anonymousUsage = anonymousUsage + messageUsage
            }
            usage = usageByMessageId.values.reduce(anonymousUsage, +)
        case .result(let result):
            usage = result.usage
            if let id = result.sessionId { sessionId = id }
        default: break
        }
    }
}
