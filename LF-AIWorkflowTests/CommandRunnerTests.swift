//
//  CommandRunnerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct CommandRunnerTests {
    private func inv(_ exe: String, _ args: [String], stdin: Data = Data()) -> ProcessInvocation {
        ProcessInvocation(executable: URL(fileURLWithPath: exe), arguments: args,
                          environment: ["PATH": "/usr/bin:/bin"],
                          workingDirectory: FileManager.default.temporaryDirectory, stdin: stdin)
    }

    private func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    @Test func capturesStdout() async throws {
        let r = try await CommandRunner.run(inv("/bin/echo", ["hi"]), timeout: .seconds(5))
        #expect(r.status == 0)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "hi\n")
        #expect(!r.truncated)
    }

    @Test func reportsExitStatus() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "exit 3"]), timeout: .seconds(5))
        #expect(r.status == 3)
    }

    @Test func capturesStderrSeparately() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "echo out; echo err >&2"]), timeout: .seconds(5))
        #expect(String(decoding: r.stdout, as: UTF8.self) == "out\n")
        #expect(String(decoding: r.stderr, as: UTF8.self) == "err\n")
    }

    @Test func passesStdin() async throws {
        let r = try await CommandRunner.run(inv("/bin/cat", [], stdin: Data("abc".utf8)), timeout: .seconds(5))
        #expect(String(decoding: r.stdout, as: UTF8.self) == "abc")
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "/usr/bin/yes | head -c 1048576"]), timeout: .seconds(20))
        #expect(r.stdout.count == 1_048_576)
        #expect(!r.truncated)
    }

    @Test func capTruncates() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "/usr/bin/yes | head -c 1048576"]),
                                            timeout: .seconds(20), maxOutputBytes: 1024)
        #expect(r.truncated)
        #expect(r.stdout.count == 1024)
    }

    @Test func timeoutKillsChild() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID()).pid")
        defer { try? FileManager.default.removeItem(at: marker) }
        let start = ContinuousClock.now
        await #expect(throws: CommandError.timedOut(after: .milliseconds(200))) {
            _ = try await CommandRunner.run(inv("/bin/sh", ["-c", "echo $$ > \(marker.path); exec /bin/sleep 5"]),
                                            timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(3))
        let pid = Int32(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        #expect(!alive(pid))
    }

    @Test func missingExecutableFailsToSpawn() async {
        do {
            _ = try await CommandRunner.run(inv("/nonexistent/lf-tool", []), timeout: .seconds(2))
            Issue.record("expected spawnFailed")
        } catch {
            guard case .spawnFailed = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func cancellationKillsChild() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID()).pid")
        defer { try? FileManager.default.removeItem(at: marker) }
        let command = inv("/bin/sh", ["-c", "echo $$ > \(marker.path); exec /bin/sleep 30"])
        let task = Task { try await CommandRunner.run(command, timeout: .seconds(60)) }
        var pid: Int32?
        for _ in 0..<100 {
            if let s = try? String(contentsOf: marker, encoding: .utf8),
               let p = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) { pid = p; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let child = try #require(pid)
        task.cancel()
        _ = try? await task.value
        var gone = false
        for _ in 0..<60 {
            if !alive(child) { gone = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(gone)
    }

    // MARK: - Process group (TD-024)

    /// Child script that starts a long-lived grandchild; both pids are written to files.
    private func groupScript(_ dir: URL, grandchildBody: String = "exec /bin/sleep 60") -> ProcessInvocation {
        inv("/bin/sh", ["-c", """
            /bin/sh -c 'echo $$ > "\(dir.path)/gc.pid"; \(grandchildBody)' &
            echo $$ > "\(dir.path)/child.pid"
            wait
            """])
    }

    @Test func timeoutKillsGrandchildren() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let command = groupScript(dir)
        let start = ContinuousClock.now
        await #expect(throws: CommandError.timedOut(after: .milliseconds(500))) {
            _ = try await CommandRunner.run(command, timeout: .milliseconds(500))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
        let child = try #require(try await TestEnv.readPid(dir.appendingPathComponent("child.pid")))
        let grandchild = try #require(try await TestEnv.readPid(dir.appendingPathComponent("gc.pid")))
        #expect(!TestEnv.alive(child))
        #expect(try await TestEnv.waitUntilGone(grandchild), "grandchild survived the timeout")
    }

    @Test func cancellationKillsGrandchildren() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let command = groupScript(dir)
        let task = Task { try await CommandRunner.run(command, timeout: .seconds(60)) }
        let grandchild = try #require(try await TestEnv.readPid(dir.appendingPathComponent("gc.pid")))
        _ = try #require(try await TestEnv.readPid(dir.appendingPathComponent("child.pid")))
        task.cancel()
        _ = try? await task.value
        #expect(try await TestEnv.waitUntilGone(grandchild), "grandchild survived cancellation")
    }

    @Test func grandchildIgnoringSigtermIsKilledAfterGrace() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let command = groupScript(dir, grandchildBody: "trap \"\" TERM; while true; do /bin/sleep 1; done")
        let start = ContinuousClock.now
        _ = try? await CommandRunner.run(command, timeout: .milliseconds(500))
        #expect(ContinuousClock.now - start < .seconds(8))
        let grandchild = try #require(try await TestEnv.readPid(dir.appendingPathComponent("gc.pid")))
        #expect(!TestEnv.alive(grandchild), "run returned while the grandchild was still alive")
    }

    @Test func childRunsInItsOwnProcessGroup() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "ps -o pgid= -p $$; echo $$"]), timeout: .seconds(5))
        let lines = String(decoding: r.stdout, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.count == 2)
        #expect(lines.first == lines.last)   // pgid == pid: the child leads its own group
        #expect(getpgrp() != Int32(lines.first ?? "") )
    }

    @Test func signalDeathReportsShellStyleStatus() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "kill -KILL $$"]), timeout: .seconds(5))
        #expect(r.status == 128 + SIGKILL)
    }

    @Test func childInheritsNoExtraDescriptors() async throws {
        let r = try await CommandRunner.run(inv("/bin/sh", ["-c", "ls /dev/fd | /usr/bin/sort -n | /usr/bin/tr '\\n' ' '"]),
                                            timeout: .seconds(5))
        let fds = String(decoding: r.stdout, as: UTF8.self).split(separator: " ").compactMap { Int($0) }
        #expect(fds.allSatisfy { $0 <= 4 }, "unexpected descriptors \(fds)")
    }

    // MARK: TD-030 / TD-116 / TD-107 (tech-debt pass S7)

    private func openFDCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    @Test func terminatePathReleasesReadHandlesWhenStrayHoldsPipe() async throws {
        // A child in another session keeps the write end open past the SIGTERM end (TD-030).
        let script = "/usr/bin/perl -e 'use POSIX; if (fork == 0) { POSIX::setsid(); exec \"sleep\", \"4\" } sleep 30'"
        // Other suites open fds concurrently, so retry: a real leak (>= 2 fds per run) fails every attempt.
        var smallestGrowth = Int.max
        for _ in 0..<3 where smallestGrowth >= 5 {
            let before = openFDCount()
            for _ in 0..<5 {
                await #expect(throws: CommandError.timedOut(after: .milliseconds(150))) {
                    _ = try await CommandRunner.run(inv("/bin/sh", ["-c", script]), timeout: .milliseconds(150))
                }
            }
            smallestGrowth = min(smallestGrowth, openFDCount() - before)
        }
        #expect(smallestGrowth < 5, "leaked read fds: \(smallestGrowth)")
    }

    @Test func resumesWhenTerminationHandlerNeverFires() async throws {
        // TD-116: the termination handler never runs; completion must fall back after reapLimit.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let run = RunningCommand(maxBytes: 1024, timeout: .seconds(1))
        run.started(pid: child.processIdentifier)
        run.cancel()
        let start = ContinuousClock.now
        let result = await run.completion()
        child.waitUntilExit()
        #expect(ContinuousClock.now - start < CommandRunner.killGrace + CommandRunner.reapLimit + .seconds(2))
        if case .success(let r) = result { #expect(r.status != 0) } else { Issue.record("expected success result") }
    }

    @Test func sigtermIgnoringFloodingChildIsKilledAndReturns() async throws {
        // TD-107 on the runner: trap TERM, flood stdout; SIGKILL after killGrace must end it.
        let start = ContinuousClock.now
        await #expect(throws: CommandError.timedOut(after: .milliseconds(200))) {
            _ = try await CommandRunner.run(inv("/bin/sh", ["-c", "trap '' TERM; while :; do echo flood; done"]),
                                            timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(8))
    }
}
