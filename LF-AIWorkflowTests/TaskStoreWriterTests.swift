//
//  TaskStoreWriterTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import os
import Testing
@testable import LF_AIWorkflow

/// Counts saves; optionally blocks each save for `delay` (a slow disk).
final class CountingStore: TaskPersisting {
    private let state = OSAllocatedUnfairLock(initialState: (saves: [[WorkflowTask]](), stored: [WorkflowTask]()))
    private let delay: TimeInterval
    init(delay: TimeInterval = 0, stored: [WorkflowTask] = []) {
        self.delay = delay
        state.withLock { $0.stored = stored }
    }
    var saves: [[WorkflowTask]] { state.withLock { $0.saves } }
    func load() -> [WorkflowTask] { state.withLock { $0.stored } }
    func save(_ tasks: [WorkflowTask]) {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        state.withLock { $0.saves.append(tasks) }
    }
}

/// TD-123 and TD-108: debounced single-writer persistence and file I/O off the engine actor.
@Suite(.timeLimit(.minutes(3)))
struct TaskStoreWriterTests {
    @Test func fiftyPublishesInsideTheWindowCauseOneWrite() async throws {
        let store = CountingStore()
        let writer = TaskStoreWriter(store: store, debounce: .seconds(60))
        for i in 0..<50 { writer.schedule([WorkflowModelTests.makeTask().with(sessionId: "t\(i)")]) }
        await writer.flush()
        #expect(store.saves.count == 1)
        #expect(store.saves.first?.first?.sessionId == "t49")
    }

    @Test func aQuietPeriodWritesTheLatestStateWithoutAFlush() async throws {
        let store = CountingStore()
        let writer = TaskStoreWriter(store: store, debounce: .milliseconds(20))
        writer.schedule([WorkflowModelTests.makeTask().with(sessionId: "late")])
        try await waitUntil("debounced write") { store.saves.count == 1 }
        #expect(store.saves.first?.first?.sessionId == "late")
    }

    @Test func flushWithNothingPendingWritesNothing() async {
        let store = CountingStore()
        let writer = TaskStoreWriter(store: store, debounce: .seconds(60))
        await writer.flush()
        #expect(store.saves.isEmpty)
    }

    @Test func engineStopFlushesTheLatestState() async throws {
        let store = CountingStore()
        let h = try Harness(store: store, persistDebounce: .seconds(60))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(store.saves.isEmpty)
        await h.engine.stop()
        #expect(store.saves.count == 1)
        #expect(store.saves.first?.first { $0.id == id }?.state == .awaitingApproval)
    }

    @Test func enginePublishDoesNotWaitForTheDisk() async throws {
        let store = CountingStore(delay: 1.5)
        let h = try Harness(store: store, persistDebounce: .milliseconds(1))
        let started = ContinuousClock.now
        _ = await h.engine.submit(h.draft())
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(await h.recorder.wait(.awaitingApproval))
    }

    @Test func restoreLoadsThroughTheWriter() async throws {
        let saved = WorkflowModelTests.makeTask().with(state: .awaitingApproval)
        let h = try Harness(store: CountingStore(stored: [saved]))
        #expect(await h.engine.restore() == 1)
        #expect(await h.engine.task(saved.id)?.state == .awaitingApproval)
    }

    @Test func projectFileWriteStillRefusesASymlinkedDirectory() async throws {
        let root = try TestEnv.makeTempDir(), outside = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".claude/plans"), withDestinationURL: outside)
        let writer = TaskStoreWriter(store: nil, debounce: .seconds(60))
        await #expect(throws: SafeProjectFile.Failure.self) {
            try await writer.writeProjectFile("x", to: ".claude/plans", name: "a.md", root: root)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: outside.path))?.isEmpty == true)
    }

    @Test func projectFileWriteAndExistsCheckRunOnTheWriter() async throws {
        let root = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = TaskStoreWriter(store: nil, debounce: .seconds(60))
        let url = try await writer.writeProjectFile("hi", to: ".claude/plans", name: "a.md", root: root)
        #expect(try String(contentsOf: url, encoding: .utf8) == "hi")
        #expect(await writer.fileExists(at: url))
        #expect(await !writer.fileExists(at: root.appendingPathComponent("nope")))
    }
}
