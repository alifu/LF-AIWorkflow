//
//  PTYProcessTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.serialized, .timeLimit(.minutes(1)))
struct PTYProcessTests {

    static func shell(_ script: String, stdin: Data = Data(), args: [String] = []) -> ProcessInvocation {
        ProcessInvocation(executable: URL(fileURLWithPath: "/bin/sh"),
                          arguments: ["-c", script] + args,
                          environment: ["PATH": "/usr/bin:/bin"],
                          workingDirectory: URL(fileURLWithPath: "/"),
                          stdin: stdin)
    }

    private func collect(_ process: PTYProcess) async -> (data: Data, status: Int32?) {
        var data = Data()
        var status: Int32?
        for await out in process.output {
            switch out {
            case .data(let d): data.append(d)
            case .exited(let s): status = s
            }
        }
        return (data, status)
    }

    @Test func catEchoesStdinThenExitsZero() async throws {
        let p = try PTYProcess.spawn(Self.shell("cat", stdin: Data("hello pty\n".utf8)))
        let r = await collect(p)
        #expect(String(decoding: r.data, as: UTF8.self).contains("hello pty"))
        #expect(r.status == 0)
    }

    @Test func largeStdinDoesNotDeadlock() async throws {
        let size = 1_048_576
        let p = try PTYProcess.spawn(Self.shell("wc -c", stdin: Data(repeating: 0x61, count: size)))
        let r = await collect(p)
        #expect(String(decoding: r.data, as: UTF8.self).contains("1048576"))
        #expect(r.status == 0)
    }

    @Test func terminateYieldsExit143() async throws {
        let p = try PTYProcess.spawn(Self.shell("sleep 30"))
        let start = ContinuousClock.now
        p.terminate()
        p.terminate()  // idempotent
        let r = await collect(p)
        #expect(r.status == 143)
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func missingExecutableThrowsENOENT() {
        let inv = ProcessInvocation(executable: URL(fileURLWithPath: "/nonexistent/lf-nope"), arguments: [],
                                    environment: [:], workingDirectory: URL(fileURLWithPath: "/"), stdin: Data())
        #expect(throws: LFCoreError.posix(ENOENT)) { try PTYProcess.spawn(inv) }
    }

    @Test func exitedChildIsReaped() async throws {
        let p = try PTYProcess.spawn(Self.shell("exit 3"))
        let pid = p.pid
        let r = await collect(p)
        #expect(r.status == 3)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
