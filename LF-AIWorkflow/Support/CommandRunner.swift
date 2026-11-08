//
//  CommandRunner.swift
//  LF-AIWorkflow
//

import Foundation
import os

nonisolated struct CommandResult: Sendable, Equatable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let truncated: Bool
}

nonisolated enum CommandError: Error, Sendable, Equatable {
    case spawnFailed(String)
    case timedOut(after: Duration)
}

/// Runs one plain (non-PTY) child with captured pipes. The only `Process.run()` call site in the app (TD-014):
/// pipes are created and the child spawned inside `SpawnGate`. Foundation starts the child as leader of its own
/// process group (`CommandRunnerTests.childRunsInItsOwnProcessGroup` guards this), so timeout and cancellation
/// signal the whole group, descendants included (TD-024).
nonisolated enum CommandRunner {
    static let killGrace: Duration = .seconds(2)
    /// After SIGKILL, how long to wait for the group to disappear before giving up.
    static let reapLimit: Duration = .seconds(1)

    /// Spawns `inv`, drains stdout/stderr concurrently (so output beyond the 64 KB pipe buffer cannot deadlock),
    /// and returns after both pipes hit EOF and the child exited. On timeout the child's whole process group gets
    /// SIGTERM, then SIGKILL after `killGrace`; `run` returns only once the group is gone (or `reapLimit` after the
    /// SIGKILL). Cancelling the calling task terminates the group the same way. A signal death reports
    /// `128 + signal` as the status. Each stream is capped at `maxOutputBytes`; extra bytes are dropped.
    /// Complexity: O(n) time in output bytes, O(min(n, maxOutputBytes)) space
    @concurrent static func run(_ inv: ProcessInvocation, timeout: Duration,
                                maxOutputBytes: Int = 8 << 20) async throws(CommandError) -> CommandResult {
        let run = RunningCommand(maxBytes: maxOutputBytes, timeout: timeout)
        // Off the cooperative pool: the gate may be held by another spawn for a long exec (TD-055).
        let spawned = try await SpawnGate.runOffPool { () throws(CommandError) -> Spawned in
            let process = Process()
            process.executableURL = inv.executable
            process.arguments = inv.arguments
            process.environment = inv.environment
            process.currentDirectoryURL = inv.workingDirectory
            process.terminationHandler = { [run] proc in
                let signalled = proc.terminationReason == .uncaughtSignal
                run.exited(status: signalled ? 128 + proc.terminationStatus : proc.terminationStatus)
            }
            // Pipes are created, marked close-on-exec and the child spawned under the gate, so no concurrent spawn
            // (e.g. a forkpty window) can inherit them. Whether Foundation's spawn closes non-CLOEXEC parent
            // descriptors varies (a probe test leaked the fd when run alone but not in the full suite), so `process.run()`
            // stays under the gate (TD-120).
            return try SpawnGate.withLock { () throws(CommandError) -> Spawned in
                let pipes = Pipes.make(hasStdin: !inv.stdin.isEmpty)
                process.standardInput = pipes.stdin ?? FileHandle.nullDevice
                process.standardOutput = pipes.stdout
                process.standardError = pipes.stderr
                do { try process.run() } catch {
                    pipes.closeAll()
                    throw .spawnFailed(error.localizedDescription)
                }
                pipes.closeParentEndsOfChild()
                return Spawned(pid: process.processIdentifier, pipes: pipes)
            }
        }
        let pipes = spawned.pipes
        run.started(pid: spawned.pid, cleanup: { pipes.stopReading() })
        pipes.startDraining(into: run)
        pipes.feed(inv.stdin)

        let timer = Task {
            try await Task.sleep(for: timeout)
            run.timeOut()
        }
        let result = await withTaskCancellationHandler {
            await run.completion()
        } onCancel: {
            run.cancel()
        }
        timer.cancel()
        return try result.get()
    }
}

/// What a successful spawn hands back to the caller: the child's pid and its pipe ends.
private nonisolated struct Spawned: Sendable {
    let pid: pid_t
    let pipes: Pipes
}

/// Pipe handles for one child. `FileHandle`/`Pipe` are `Sendable`.
private nonisolated struct Pipes: Sendable {
    let stdin: Pipe?
    let stdout: Pipe
    let stderr: Pipe

    /// Creates the pipes with every descriptor close-on-exec; Foundation dup2s the child ends onto 0/1/2.
    static func make(hasStdin: Bool) -> Pipes {
        let pipes = Pipes(stdin: hasStdin ? Pipe() : nil, stdout: Pipe(), stderr: Pipe())
        for pipe in [pipes.stdin, pipes.stdout, pipes.stderr].compactMap({ $0 }) {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
            }
        }
        if let write = pipes.stdin?.fileHandleForWriting { _ = fcntl(write.fileDescriptor, F_SETNOSIGPIPE, 1) }
        return pipes
    }

    /// The child owns its ends after spawn; close ours so EOF can arrive.
    func closeParentEndsOfChild() {
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        try? stdin?.fileHandleForReading.close()
    }

    /// Drops both read handlers so the sources release their handles (the pipes close on dealloc), even if a
    /// stray process in another group still holds a write end (TD-030).
    func stopReading() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }

    func closeAll() {
        for pipe in [stdin, stdout, stderr].compactMap({ $0 }) {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
    }

    func startDraining(into run: RunningCommand) {
        for (pipe, isStdout) in [(stdout, true), (stderr, false)] {
            pipe.fileHandleForReading.readabilityHandler = { [run] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    run.eof(isStdout: isStdout)
                } else {
                    run.append(chunk, isStdout: isStdout)
                }
            }
        }
    }

    /// Writes stdin off-thread so a child that does not read cannot block the caller.
    func feed(_ data: Data) {
        guard let handle = stdin?.fileHandleForWriting else { return }
        DispatchQueue.global().async {
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}

/// Lock-guarded state shared by the pipe handlers, the termination handler, the timer and cancellation.
nonisolated final class RunningCommand: Sendable {
    private struct State {
        var out = Data()
        var err = Data()
        var truncated = false
        var outDone = false
        var errDone = false
        var status: Int32?
        var pid: pid_t?
        var timedOut = false
        var cancelled = false
        /// Set when SIGTERM went to the group; completion then also waits for `reaped`.
        var terminatedAt: ContinuousClock.Instant?
        var killSent = false
        var reaped = false   // also true once the command completed: no more signals
        var continuation: CheckedContinuation<Result<CommandResult, CommandError>, Never>?
        var cleanup: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let maxBytes: Int
    private let timeout: Duration

    init(maxBytes: Int, timeout: Duration) {
        self.maxBytes = max(0, maxBytes)
        self.timeout = timeout
    }

    func started(pid: pid_t, cleanup: (@Sendable () -> Void)? = nil) {
        let shouldKill = state.withLock { s -> Bool in
            s.pid = pid
            s.cleanup = cleanup
            return s.cancelled && !s.reaped
        }
        if shouldKill { terminate() }
    }

    func append(_ chunk: Data, isStdout: Bool) {
        state.withLock { s in
            let current = isStdout ? s.out.count : s.err.count
            let room = max(0, maxBytes - current)
            if chunk.count > room { s.truncated = true }
            let kept = chunk.prefix(room)
            if isStdout { s.out.append(kept) } else { s.err.append(kept) }
        }
    }

    func eof(isStdout: Bool) {
        state.withLock { s in
            if isStdout { s.outDone = true } else { s.errDone = true }
        }
        resumeIfComplete()
    }

    func exited(status: Int32) {
        state.withLock { $0.status = status }
        resumeIfComplete()
    }

    func timeOut() {
        let fire = state.withLock { s -> Bool in
            guard !s.reaped, s.terminatedAt == nil else { return false }
            s.timedOut = true
            return true
        }
        if fire { terminate() }
    }

    func cancel() {
        let fire = state.withLock { s -> Bool in
            s.cancelled = true
            return !s.reaped && s.pid != nil
        }
        if fire { terminate() }
    }

    func completion() async -> Result<CommandResult, CommandError> {
        await withCheckedContinuation { cont in
            state.withLock { $0.continuation = cont }
            resumeIfComplete()
        }
    }

    /// SIGTERM to the process group now; `reapTick` escalates to SIGKILL and decides when the group is gone.
    private func terminate() {
        let pid = state.withLock { s -> pid_t? in
            guard s.terminatedAt == nil, let pid = s.pid else { return nil }
            s.terminatedAt = .now
            return pid
        }
        guard let pid else { return }
        kill(-pid, SIGTERM)
        scheduleReapTick()
    }

    private static let tickInterval: DispatchTimeInterval = .milliseconds(20)

    private func scheduleReapTick() {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.tickInterval) { [self] in reapTick() }
    }

    /// Polls every 20 ms: SIGKILL once the grace passed, finish once the child is reaped and its group has no
    /// members left (or `reapLimit` after the SIGKILL).
    private func reapTick() {
        enum Step { case again, finished }
        let step = state.withLock { s -> Step in
            guard let pid = s.pid, let started = s.terminatedAt, !s.reaped else { return .finished }
            let elapsed = ContinuousClock.now - started
            let groupGone = kill(-pid, 0) != 0
            if s.status != nil, groupGone {
                s.reaped = true
                return .finished
            }
            if !s.killSent, elapsed >= CommandRunner.killGrace {
                s.killSent = true
                kill(-pid, SIGKILL)
            } else if s.killSent, elapsed >= CommandRunner.killGrace + CommandRunner.reapLimit {
                s.reaped = true
                return .finished
            }
            return .again
        }
        switch step {
        case .again: scheduleReapTick()
        case .finished: resumeIfComplete()
        }
    }

    /// Complexity: O(1) time, O(1) space
    private func resumeIfComplete() {
        typealias Outcome = Result<CommandResult, CommandError>
        let done: (CheckedContinuation<Outcome, Never>, Outcome, (@Sendable () -> Void)?)? =
            state.withLock { s in
                guard let cont = s.continuation else { return nil }
                // After SIGTERM the group is hunted down by `reapTick`; do not wait for stragglers' EOF.
                // If the termination handler never fired, the reap fallback reports a SIGKILL death (TD-116).
                let terminated = s.terminatedAt != nil
                let drained = terminated ? s.reaped : (s.outDone && s.errDone)
                guard drained, let status = s.status ?? (terminated ? 128 + SIGKILL : nil) else { return nil }
                s.continuation = nil
                s.reaped = true   // completed: never signal this pid again (it may be reused)
                let cleanup = terminated ? s.cleanup : nil
                s.cleanup = nil
                let result: Outcome = s.timedOut
                    ? .failure(.timedOut(after: timeout))
                    : .success(CommandResult(status: status, stdout: s.out, stderr: s.err, truncated: s.truncated))
                return (cont, result, cleanup)
            }
        guard let (cont, result, cleanup) = done else { return }
        cleanup?()
        cont.resume(returning: result)
    }
}
