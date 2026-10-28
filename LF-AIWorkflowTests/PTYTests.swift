//
//  PTYTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

@Suite(.serialized, .timeLimit(.minutes(1)))
struct PTYTests {

    /// Spawns a command, keeping argv/envp storage alive for the call.
    private func spawn(_ argv: [String], env: [String]? = nil, cwd: String? = nil, stdinPipe: Bool = false) -> OpaquePointer? {
        let a = CStringArray(argv)
        let e = env.map { CStringArray($0) }
        return withExtendedLifetime((a, e)) {
            var o = lf_pty_options(argv: a.pointer, envp: e?.pointer, cwd: nil, cols: 0, rows: 0, stdin_pipe: stdinPipe ? 1 : 0)
            if let cwd {
                return cwd.withCString { c in
                    o.cwd = c
                    return lf_pty_spawn(&o)
                }
            }
            return lf_pty_spawn(&o)
        }
    }

    /// Reads until EOF or the child exits and the pipe drains.
    private func readAll(_ p: OpaquePointer) -> Data {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = lf_pty_read(p, &buf, buf.count)
            if n > 0 { out.append(buf, count: n); continue }
            if n == 0 { break }
            if errno == EAGAIN { _ = lf_pty_wait_event(p, 1000); continue }
            break
        }
        return out
    }

    private func exited(_ p: OpaquePointer) -> Int32 {
        var st: Int32 = -1
        #expect(lf_pty_wait(p, &st) == 0)
        return st
    }

    @Test func echoHelloReachesEOFWithStatusZero() throws {
        let p = try #require(spawn(["/bin/echo", "hello"]))
        defer { lf_pty_destroy(p) }
        let out = String(decoding: readAll(p), as: UTF8.self)
        #expect(out.contains("hello\r\n"))
        #expect(exited(p) == 0)
    }

    @Test func catEchoesWithoutDuplicateAndEOFExitsZero() throws {
        let p = try #require(spawn(["/bin/cat"]))
        defer { lf_pty_destroy(p) }
        #expect(lf_pty_write(p, "abc\n", 4) == 4)
        var got = Data()
        var buf = [UInt8](repeating: 0, count: 64)
        while got.count < 5 {
            let n = lf_pty_read(p, &buf, buf.count)
            if n > 0 { got.append(buf, count: n) } else { _ = lf_pty_wait_event(p, 1000) }
        }
        #expect(String(decoding: got, as: UTF8.self) == "abc\r\n")
        #expect(lf_pty_send_eof(p) == 0)
        #expect(exited(p) == 0)
    }

    @Test func shellExitStatusIsPropagated() throws {
        let p = try #require(spawn(["/bin/sh", "-c", "exit 3"]))
        defer { lf_pty_destroy(p) }
        #expect(exited(p) == 3)
        #expect(lf_pty_pid(p) > 0)
    }

    @Test func nonexistentPathFailsWithENOENT() {
        errno = 0
        let p = spawn(["/nonexistent/lf-binary"])
        #expect(p == nil)
        #expect(errno == ENOENT)
    }

    @Test func invalidOptionsFailWithEINVAL() {
        errno = 0
        #expect(lf_pty_spawn(nil) == nil)
        #expect(errno == EINVAL)
        var o = lf_pty_options(argv: nil, envp: nil, cwd: nil, cols: 0, rows: 0, stdin_pipe: 0)
        errno = 0
        #expect(lf_pty_spawn(&o) == nil)
        #expect(errno == EINVAL)
        let empty = CStringArray([])
        o.argv = empty.pointer
        errno = 0
        #expect(lf_pty_spawn(&o) == nil)
        #expect(errno == EINVAL)
    }

    @Test func nullHandleCallsFailSafely() {
        errno = 0
        #expect(lf_pty_read(nil, nil, 0) == -1)
        #expect(lf_pty_write(nil, nil, 0) == -1)
        #expect(lf_pty_send_eof(nil) == -1)
        #expect(lf_pty_wait_event(nil, 0) == -1)
        #expect(lf_pty_terminate(nil, 0) == -1)
        #expect(lf_pty_wait(nil, nil) == -1)
        #expect(lf_pty_pid(nil) == -1)
        lf_pty_destroy(nil)
    }

    @Test func cwdIsHonored() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lfpty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.resolvingSymlinksInPath().path
        let p = try #require(spawn(["/bin/pwd"], cwd: dir.path))
        defer { lf_pty_destroy(p) }
        let out = String(decoding: readAll(p), as: UTF8.self)
        #expect(out.contains(real))
    }

    @Test func badCwdFailsWithENOENT() {
        errno = 0
        #expect(spawn(["/bin/pwd"], cwd: "/nonexistent/lf-dir") == nil)
        #expect(errno == ENOENT)
    }

    @Test func envpIsHonored() throws {
        let p = try #require(spawn(["/usr/bin/env"], env: ["LF_TEST=1"]))
        defer { lf_pty_destroy(p) }
        let out = String(decoding: readAll(p), as: UTF8.self)
        #expect(out.contains("LF_TEST=1"))
        #expect(!out.contains("HOME="))
    }

    @Test func waitEventTimesOutWithZero() throws {
        let p = try #require(spawn(["/bin/sleep", "30"]))
        defer { lf_pty_destroy(p) }
        let start = ContinuousClock.now
        #expect(lf_pty_wait_event(p, 200) == 0)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed >= .milliseconds(150) && elapsed < .seconds(2))
    }

    @Test func waitEventReportsExit() throws {
        let p = try #require(spawn(["/bin/sh", "-c", "exit 0"]))
        defer { lf_pty_destroy(p) }
        // EOF on the master is level-triggered, so wait_event can return READABLE at once,
        // before NOTE_EXIT arrives. Poll against a deadline and back off on READABLE-only results.
        let deadline = ContinuousClock.now + .seconds(5)
        var mask = 0
        while mask & Int(LF_PTY_EXITED) == 0 && ContinuousClock.now < deadline {
            let result = Int(lf_pty_wait_event(p, 100))
            #expect(result >= 0)
            if result < 0 { break }
            mask |= result
            if mask & Int(LF_PTY_EXITED) == 0 { Thread.sleep(forTimeInterval: 0.005) }
        }
        #expect(mask & Int(LF_PTY_EXITED) != 0)
        #expect(Int(lf_pty_wait_event(p, 0)) & Int(LF_PTY_EXITED) != 0)  // sticky
    }

    @Test func waitEventAfterEOFDoesNotSpin() throws {
        // On macOS the pty master only reports EOF once the child (session leader) is gone,
        // so EOF and exit coincide; the level-triggered READ filter must still not be reported again.
        let p = try #require(spawn(["/bin/sh", "-c", "exit 0"]))
        defer { lf_pty_destroy(p) }
        _ = readAll(p)
        var mask = 0
        var calls = 0
        let deadline = ContinuousClock.now + .seconds(5)
        while mask & Int(LF_PTY_EXITED) == 0 && ContinuousClock.now < deadline {
            let r = Int(lf_pty_wait_event(p, 100))
            calls += 1
            #expect(r >= 0)
            if r < 0 { break }
            #expect(r & Int(LF_PTY_READABLE) == 0)
            mask |= r
        }
        #expect(mask & Int(LF_PTY_EXITED) != 0)
        #expect(Int(lf_pty_wait_event(p, 100)) == Int(LF_PTY_EXITED))  // sticky, and no READABLE
        #expect(calls < 10)
    }

    private func expectNoZombie(_ pid: Int32) {
        errno = 0
        #expect(waitpid(pid, nil, WNOHANG) == -1 && errno == ECHILD)
        errno = 0
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @Test func sigtermPathReportsStatus143() throws {
        let p = try #require(spawn(["/bin/sleep", "30"]))
        defer { lf_pty_destroy(p) }
        let pid = lf_pty_pid(p)
        let start = ContinuousClock.now
        #expect(lf_pty_terminate(p, 500) == 128 + SIGTERM)
        #expect(ContinuousClock.now - start < .seconds(2))
        expectNoZombie(pid)
        #expect(lf_pty_terminate(p, 500) == 128 + SIGTERM)  // idempotent
    }

    @Test func sigkillEscalationReportsStatus137() throws {
        let p = try #require(spawn(["/bin/sh", "-c", "trap '' TERM; sleep 30"]))
        defer { lf_pty_destroy(p) }
        let pid = lf_pty_pid(p)
        Thread.sleep(forTimeInterval: 0.3)  // let the trap install
        let start = ContinuousClock.now
        #expect(lf_pty_terminate(p, 500) == 128 + SIGKILL)
        #expect(ContinuousClock.now - start < .seconds(2))
        expectNoZombie(pid)
    }

    @Test func destroyOnLiveChildReapsIt() throws {
        let p = try #require(spawn(["/bin/sleep", "30"]))
        let pid = lf_pty_pid(p)
        lf_pty_destroy(p)
        expectNoZombie(pid)
    }

    @Test func oneMiBThroughCatWithShortWritesRoundTrips() throws {
        let p = try #require(spawn(["/bin/cat"]))
        defer { lf_pty_destroy(p) }
        // 100-byte lines (99 + '\n') stay below the canonical-mode line limit.
        let line = String(repeating: "x", count: 99) + "\n"
        let total = 1 << 20
        let input = Data(String(repeating: line, count: total / 100).utf8)
        let expectedBytes = input.count + input.count / 100  // '\n' -> "\r\n"
        var written = 0
        var received = 0
        var buf = [UInt8](repeating: 0, count: 8192)
        var sawEAGAIN = false
        let deadline = ContinuousClock.now + .seconds(45)
        while received < expectedBytes && ContinuousClock.now < deadline {
            if written < input.count {
                let n = input.withUnsafeBytes { raw in
                    lf_pty_write(p, raw.baseAddress! + written, min(4096, input.count - written))
                }
                if n > 0 { written += n } else if errno == EAGAIN { sawEAGAIN = true }
            }
            let r = lf_pty_read(p, &buf, buf.count)
            if r > 0 { received += r } else if written >= input.count || sawEAGAIN { _ = lf_pty_wait_event(p, 20) }
        }
        #expect(written == input.count)
        #expect(received == expectedBytes)
        #expect(lf_pty_terminate(p, 200) >= 0)
    }

    @Test func stdinPipeRoundTripsLargeRawLineThroughCat() throws {
        let p = try #require(spawn(["/bin/cat"], stdinPipe: true))
        defer { lf_pty_destroy(p) }
        // One 6 KiB line with ETX, DC3, DC1 and CR; a tty would drop, signal, swallow or rewrite.
        var payload = Data()
        for i in 0..<1500 { payload.append(contentsOf: [0x41 + UInt8(i % 26), 0x03, 0x13, 0x11, 0x0D]) }
        payload.append(0x0A)
        var written = 0
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        let deadline = ContinuousClock.now + .seconds(20)
        while written < payload.count && ContinuousClock.now < deadline {
            let n = payload.withUnsafeBytes { lf_pty_write(p, $0.baseAddress! + written, payload.count - written) }
            if n > 0 { written += n } else if errno == EAGAIN { _ = lf_pty_wait_event(p, 10) }
            let r = lf_pty_read(p, &buf, buf.count)
            if r > 0 { out.append(buf, count: r) }
        }
        #expect(written == payload.count)
        #expect(lf_pty_send_eof(p) == 0)
        out.append(readAll(p))
        var expected = payload.dropLast()
        expected.append(contentsOf: [0x0D, 0x0A])  // ONLCR on the output side
        #expect(out == Data(expected))
        #expect(exited(p) == 0)
    }

    @Test func stdinPipeWriteAfterChildExitFailsWithEPIPEWithoutSIGPIPE() throws {
        let p = try #require(spawn(["/usr/bin/true"], stdinPipe: true))
        defer { lf_pty_destroy(p) }
        #expect(exited(p) == 0)
        errno = 0
        let n = [UInt8(0x41)].withUnsafeBytes { lf_pty_write(p, $0.baseAddress, 1) }
        #expect(n == -1)
        #expect(errno == EPIPE)
    }

    @Test func stdinPipeSendEofIsIdempotentAndWritesAfterEofFailWithEPIPE() throws {
        let p = try #require(spawn(["/bin/cat"], stdinPipe: true))
        defer { lf_pty_destroy(p) }
        #expect(lf_pty_send_eof(p) == 0)
        #expect(lf_pty_send_eof(p) == 0)
        errno = 0
        let n = [UInt8(0x41)].withUnsafeBytes { lf_pty_write(p, $0.baseAddress, 1) }
        #expect(n == -1)
        #expect(errno == EPIPE)
        #expect(readAll(p).isEmpty)  // nothing leaked into the tty (no ^D / data echoed)
        #expect(exited(p) == 0)
    }
}

struct CStringArrayTests {
    @Test func holdsNullTerminatedCopies() {
        let arr = CStringArray(["/bin/echo", "a b", ""])
        #expect(arr.count == 3)
        #expect(String(cString: arr.pointer[0]!) == "/bin/echo")
        #expect(String(cString: arr.pointer[1]!) == "a b")
        #expect(String(cString: arr.pointer[2]!) == "")
        #expect(arr.pointer[3] == nil)
    }
}
