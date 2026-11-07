//
//  SpawnGateTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct SpawnGateTests {
    private struct Boom: Error {}

    nonisolated(unsafe) private static var counterValue = 0

    @Test func returnsBodyResult() {
        #expect(SpawnGate.withLock { 42 } == 42)
    }

    @Test func rethrowsBodyError() {
        #expect(throws: Boom.self) { try SpawnGate.withLock { throw Boom() } }
    }

    @Test func excludesConcurrentBodies() async {
        Self.counterValue = 0
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<1000 { SpawnGate.withLock { Self.counterValue += 1 } }
                }
            }
        }
        #expect(Self.counterValue == 8000)
    }
}

/// TD-120: the gate is not held across a child's lifetime, nor across its exec.
@Suite(.timeLimit(.minutes(2)))
struct SpawnOverlapTests {
    @Test func twoLongChildrenOverlap() async throws {
        let dir = try TestEnv.makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let inv = ProcessInvocation(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"],
                                    environment: ["PATH": "/usr/bin:/bin"], workingDirectory: dir, stdin: Data())
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<2 { group.addTask { _ = try await CommandRunner.run(inv, timeout: .seconds(60)) } }
                try await group.waitForAll()
            }
        }
        #expect(elapsed < .milliseconds(3800), "two 2 s children ran serially: \(elapsed)")
    }
}
