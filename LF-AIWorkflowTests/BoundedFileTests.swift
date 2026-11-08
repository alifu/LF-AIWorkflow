//
//  BoundedFileTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct BoundedFileTests {
    @Test func readsAndTruncatesARegularFile() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, "a.txt", "hello world")
        let file = try await BoundedFile.readText(dir.appendingPathComponent("a.txt"), maxBytes: 5)
        #expect(file == BoundedFile.Text(text: "hello", isTruncated: true))
    }

    @Test(.timeLimit(.minutes(1))) func rejectsAFifoInsteadOfBlocking() async throws {
        let dir = try TestEnv.makeTempDir()
        let fifo = dir.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o644) == 0)
        await #expect(throws: (any Error).self) { try await BoundedFile.readText(fifo, maxBytes: 10) }
    }

    @Test func rejectsADirectory() async throws {
        let dir = try TestEnv.makeTempDir()
        await #expect(throws: (any Error).self) { try await BoundedFile.readText(dir, maxBytes: 10) }
    }

    @Test func throwsForAMissingFile() async throws {
        let dir = try TestEnv.makeTempDir()
        await #expect(throws: (any Error).self) { try await BoundedFile.readText(dir.appendingPathComponent("nope"), maxBytes: 10) }
    }
}
