//
//  TestHelpers.swift
//  LF-AIWorkflowTests
//

import Foundation
import os
@testable import LF_AIWorkflow

/// Shared fixtures for Phase 4 suites: temp dirs, fake CLIs, temp git repos. All spawns go through `CommandRunner`.
enum TestEnv {
    /// Environment for git in tests: no user or system config.
    static let git: [String: String] = [
        "PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory(),
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
    ]

    static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func writeExecutable(_ dir: URL, _ name: String, body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try writeScript(url, contents: "#!/bin/sh\n" + body + "\n", mode: 0o755)
        return url
    }

    /// Writes a script so it can be exec'd immediately: O_CLOEXEC (a concurrent fork cannot inherit the write fd,
    /// which would give ETXTBSY), fsync, fchmod, close, all before returning (TD-055).
    /// Complexity: O(n) time, O(1) space in the script size.
    static func writeScript(_ url: URL, contents: String, mode: mode_t = 0o755) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var failed = false
        let bytes = Array(contents.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, $0.count - offset) }
            if n <= 0 { failed = true; break }
            offset += n
        }
        if !failed { failed = fsync(fd) != 0 || fchmod(fd, mode) != 0 }
        let closeFailed = close(fd) != 0
        if failed || closeFailed { throw CocoaError(.fileWriteUnknown) }
    }

    static func write(_ dir: URL, _ relative: String, _ text: String) throws {
        let url = dir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func git(_ args: [String], in dir: URL) async throws -> String {
        let inv = ProcessInvocation(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-c", "user.name=lf", "-c", "user.email=lf@example.invalid", "-c", "commit.gpgsign=false"] + args,
            environment: git, workingDirectory: dir, stdin: Data())
        let result = try await CommandRunner.run(inv, timeout: .seconds(30))
        guard result.status == 0 else {
            throw CommandError.spawnFailed("git \(args) failed: \(String(decoding: result.stderr, as: UTF8.self))")
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    /// A repo with one commit containing `a.swift` and `Package.resolved`.
    static func makeRepo() async throws -> URL {
        let dir = try makeTempDir()
        try await git(["init", "-q", "-b", "main"], in: dir)
        try write(dir, "a.swift", "let a = 1\n")
        try write(dir, "Package.resolved", "{}\n")
        try await git(["add", "-A"], in: dir)
        try await git(["commit", "-q", "-m", "init"], in: dir)
        return dir
    }

    static func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    /// Polls for a pid file written by a fake script.
    static func readPid(_ url: URL, attempts: Int = 100) async throws -> Int32? {
        for _ in 0..<attempts {
            if let s = try? String(contentsOf: url, encoding: .utf8),
               let p = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return p }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    static func waitUntilGone(_ pid: Int32, attempts: Int = 80) async throws -> Bool {
        for _ in 0..<attempts {
            if !alive(pid) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

/// Deterministic clock: time only moves through `advance(by:)`. Sleepers register synchronously, so tests
/// can wait for them with `waitForSleepers` instead of sleeping.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper { let deadline: Instant; let continuation: CheckedContinuation<Void, any Error> }
    private struct Waiter { let count: Int; let continuation: CheckedContinuation<Void, Never> }
    private struct State { var now = Instant(offset: .zero); var sleepers: [UUID: Sleeper] = [:]; var waiters: [Waiter] = [] }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case resume, cancel, wait([Waiter]) }
                let outcome: Outcome = state.withLock { s in
                    if Task.isCancelled { return .cancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    let ready = s.waiters.filter { $0.count <= s.sleepers.count }
                    s.waiters.removeAll { $0.count <= s.sleepers.count }
                    return .wait(ready)
                }
                switch outcome {
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                case .wait(let ready): ready.forEach { $0.continuation.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Suspends until at least `count` tasks are sleeping on this clock.
    func waitForSleepers(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.sleepers.count >= count { return true }
                s.waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline passed.
    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { s in
            s.now = s.now.advanced(by: duration)
            let ids = s.sleepers.filter { $0.value.deadline <= s.now }.map(\.key)
            return ids.compactMap { s.sleepers.removeValue(forKey: $0) }
        }
        due.forEach { $0.continuation.resume() }
    }
}
