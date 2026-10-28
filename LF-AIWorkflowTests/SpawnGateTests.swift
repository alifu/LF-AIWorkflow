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
