//
//  ScriptExecStressTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

/// TD-055 root cause: macOS spends ~0.15-0.3 s, serialized, on the first exec of every newly written script
/// (a copied signed binary is instant), so bursts of fake tools stall for seconds under load. Timeouts of the
/// script-exec tests are therefore generous. This test also checks that parallel write+exec never fails (ETXTBSY).
/// Freshly written scripts must exec at once even while many other scripts are written and spawned.
@Suite(.timeLimit(.minutes(2)))
struct ScriptExecStressTests {
    @Test func fiftyParallelScriptsWriteAndExec() async throws {
        let dir = try TestEnv.makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let script = try TestEnv.writeExecutable(dir, "tool-\(i)", body: "echo \(i)")
                    let inv = ProcessInvocation(executable: script, arguments: [], environment: ["PATH": "/usr/bin:/bin"],
                                                workingDirectory: dir, stdin: Data())
                    let r = try await CommandRunner.run(inv, timeout: .seconds(100))
                    return r.status == 0 ? String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : "fail"
                }
            }
            var all: [String] = []
            for try await o in group { all.append(o) }
            return all
        }
        #expect(Set(outputs) == Set((0..<50).map(String.init)))
    }
}
