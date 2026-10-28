//
//  PTYProcess.swift
//  LF-AIWorkflow
//

import Foundation
import os
import LFCore

/// One child process under a pty, pumped on a private serial queue (never the cooperative pool).
///
/// @unchecked Sendable: `handle` and all mutable state are touched only on `queue` (serial), and in `deinit`,
/// which can only run after the pump loop released its strong reference. `output`, `pid` and the
/// continuation are immutable `Sendable` values.
nonisolated final class PTYProcess: @unchecked Sendable {
    enum Output: Sendable, Equatable {
        case data(Data)
        case exited(status: Int32)
    }

    /// Unbounded on purpose: dropping bytes would corrupt NDJSON.
    let output: AsyncStream<Output>
    let pid: Int32

    private static let readChunk = 64 * 1024
    private static let idlePollMs: Int32 = 100
    private static let stdinPollMs: Int32 = 5

    private let queue: DispatchQueue
    private let continuation: AsyncStream<Output>.Continuation
    private var handle: OpaquePointer?
    private var pendingStdin: Data
    private var stdinClosed = false
    private var terminateGraceMs: Int32?

    private init(handle: OpaquePointer, stdin: Data) {
        self.handle = handle
        self.pid = lf_pty_pid(handle)
        self.pendingStdin = stdin
        self.queue = DispatchQueue(label: "com.alifu.LF-AIWorkflow.pty.\(lf_pty_pid(handle))")
        (output, continuation) = AsyncStream.makeStream(of: Output.self, bufferingPolicy: .unbounded)
    }

    deinit {
        // Normally released in `finish`; this covers a pump that never ran.
        if let handle { lf_pty_destroy(handle) }
    }

    /// Spawns the child (inside `SpawnGate`) with a stdin pipe and starts the pump.
    /// Complexity: O(argc + envc) time, O(argc + envc) space
    static func spawn(_ invocation: ProcessInvocation, cols: UInt16 = 200, rows: UInt16 = 50) throws(LFCoreError) -> PTYProcess {
        let argv = CStringArray([invocation.executable.path] + invocation.arguments)
        let envp = CStringArray(invocation.environment.map { "\($0.key)=\($0.value)" })
        let cwd = invocation.workingDirectory.path
        let created: (handle: OpaquePointer?, error: Int32) = withExtendedLifetime((argv, envp)) {
            cwd.withCString { cwdPtr in
                var options = lf_pty_options(argv: argv.pointer, envp: envp.pointer, cwd: cwdPtr,
                                             cols: cols, rows: rows, stdin_pipe: 1)
                return SpawnGate.withLock {
                    let h = lf_pty_spawn(&options)
                    return (h, errno)
                }
            }
        }
        guard let handle = created.handle else { throw .posix(created.error) }
        let process = PTYProcess(handle: handle, stdin: invocation.stdin)
        process.queue.async { process.pump() }
        return process
    }

    /// Idempotent. SIGTERM to the process group, SIGKILL after `graceMs`; the stream then yields `.exited` and ends.
    /// Complexity: O(1) time, O(1) space
    func terminate(graceMs: Int32 = 2000) {
        queue.async { [self] in
            if terminateGraceMs == nil { terminateGraceMs = graceMs }
        }
    }

    // MARK: - Pump (queue only)

    /// One iteration per `queue.async`, so `terminate` interleaves.
    /// Complexity: O(chunk) time per iteration, O(chunk) space
    private func pump() {
        guard let handle else { return }
        if let grace = terminateGraceMs {
            let status = lf_pty_terminate(handle, grace)
            return finish(status: status < 0 ? 137 : status)
        }
        pushStdin(handle)
        let events = lf_pty_wait_event(handle, pendingStdin.isEmpty ? Self.idlePollMs : Self.stdinPollMs)
        if events < 0 {
            AppLog.claude.error("pty wait failed errno=\(errno)")
            terminateGraceMs = 0
        } else {
            if events & Int32(LF_PTY_READABLE) != 0 || events & Int32(LF_PTY_EXITED) != 0 { drain(handle) }
            if events & Int32(LF_PTY_EXITED) != 0 {
                var status: Int32 = 0
                _ = lf_pty_wait(handle, &status)
                return finish(status: status)
            }
        }
        queue.async { [self] in pump() }
    }

    /// Writes as much pending stdin as the pipe takes; EOF once done or on EPIPE.
    private func pushStdin(_ handle: OpaquePointer) {
        guard !stdinClosed else { return }
        while !pendingStdin.isEmpty {
            let written = pendingStdin.withUnsafeBytes { lf_pty_write(handle, $0.baseAddress, $0.count) }
            if written > 0 {
                pendingStdin = pendingStdin.dropFirst(written).withUnsafeBytes { Data($0) }
                continue
            }
            if errno == EAGAIN || errno == EINTR { return }
            pendingStdin = Data()  // EPIPE or hard error: the child no longer reads
        }
        _ = lf_pty_send_eof(handle)
        stdinClosed = true
    }

    /// Reads until EAGAIN or EOF, yielding each chunk.
    private func drain(_ handle: OpaquePointer) {
        var buffer = [UInt8](repeating: 0, count: Self.readChunk)
        while true {
            let n = buffer.withUnsafeMutableBytes { lf_pty_read(handle, $0.baseAddress, $0.count) }
            if n > 0 {
                continuation.yield(.data(Data(buffer[0..<n])))
            } else {
                return
            }
        }
    }

    private func finish(status: Int32) {
        if let handle { lf_pty_destroy(handle) }
        handle = nil
        continuation.yield(.exited(status: status))
        continuation.finish()
    }
}
