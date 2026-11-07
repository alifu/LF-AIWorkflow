//
//  ProjectStoreTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

/// Task persistence (TD-028), `finishedAt` (TD-039) and settings pruning (TD-071).
struct ProjectStoreTests {
    private func store() throws -> (ProjectStore, URL) {
        let dir = try TestEnv.makeTempDir()
        return (ProjectStore(fileURL: dir.appendingPathComponent("sub/tasks.json")), dir)
    }

    private func richTask() -> WorkflowTask {
        WorkflowModelTests.makeTask()
            .with(state: .awaitingInput).with(waiting: .budgetExceeded(spent: 5, limit: 3), resume: .code)
            .with(failure: .claudeError("x")).with(sessionId: "s")
            .with(worktree: Worktree(path: URL(fileURLWithPath: "/w"), branch: "b", baseCommit: "c"))
            .adding(usage: TokenUsage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4), for: .plan)
            .with(finishedAt: Date(timeIntervalSince1970: 99))
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tasks = [richTask(), WorkflowModelTests.makeTask()]
        store.save(tasks)
        #expect(Set(store.load().map(\.id)) == Set(tasks.map(\.id)))
        let loaded = try #require(store.load().first { $0.id == tasks[0].id })
        #expect(loaded == tasks[0])
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.load().isEmpty)
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test func unknownVersionLoadsEmpty() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":99,"tasks":[]}"#.utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test func corruptFileIsBackedUpAndALaterSaveKeepsTheBackup() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
        let backups = FileBackup.backups(of: store.fileURL)
        #expect(backups.count == 1)
        store.save([WorkflowModelTests.makeTask()])
        #expect(try Data(contentsOf: backups[0]) == Data("not json".utf8))
        #expect(store.load().count == 1)
    }

    @Test func unknownVersionIsBackedUpAndKept() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"version":99,"tasks":[]}"#.utf8)
        try original.write(to: store.fileURL)
        _ = store.load()
        store.save([])
        let backups = FileBackup.backups(of: store.fileURL)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
    }

    @Test func atMostThreeBackupsAreKept() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for stamp in 1...5 {
            try Data("bad".utf8).write(to: store.fileURL)
            FileBackup.preserve(store.fileURL, now: Date(timeIntervalSince1970: Double(stamp)))
        }
        let names = FileBackup.backups(of: store.fileURL).map(\.lastPathComponent)
        #expect(names == ["tasks.json.bak-3", "tasks.json.bak-4", "tasks.json.bak-5"])
    }

    @Test func baseCommitRoundTripsAndOldFilesDecodeNil() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = WorkflowModelTests.makeTask().with(baseCommit: "abc")
        store.save([task])
        #expect(store.load().first?.baseCommit == "abc")
        let encoder = JSONEncoder.epochMillis
        let json = try #require(String(data: encoder.encode(WorkflowModelTests.makeTask()), encoding: .utf8))
        let stripped = json.replacingOccurrences(of: #","baseCommit":null"#, with: "")
        let decoded = try JSONDecoder.epochMillis.decode(WorkflowTask.self, from: Data(stripped.utf8))
        #expect(decoded.baseCommit == nil)
    }

    @Test func finishedTasksAreCapped() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let done = (0..<(ProjectStore.maxFinished + 5)).map { _ in WorkflowModelTests.makeTask().with(state: .done) }
        store.save(done + [WorkflowModelTests.makeTask()])
        let loaded = store.load()
        #expect(loaded.filter { $0.state == .done }.count == ProjectStore.maxFinished)
        #expect(loaded.contains { $0.state == .queued })
    }

    @Test func runningTasksReloadParked() {
        let now = Date(timeIntervalSince1970: 5)
        let base = WorkflowModelTests.makeTask()
        let out = TaskRestore.interrupted([base.with(state: .code), base.with(state: .awaitingApproval),
                                           base.with(state: .done), base], now: now)
        #expect(out[0].state == .awaitingInput && out[0].resumeState == .code)
        #expect(out[0].waitReason == .other(TaskRestore.interruptedText))
        #expect(out[1].state == .awaitingApproval)
        #expect(out[2].state == .done)
        #expect(out[3].state == .failed && out[3].finishedAt == now)
    }

    @Test func finishedAtIsSetOnceByTheTransition() throws {
        let first = Date(timeIntervalSince1970: 10), later = Date(timeIntervalSince1970: 20)
        let task = WorkflowModelTests.makeTask()
        #expect(task.finishedAt == nil)
        let active = try TaskTransitions.move(task, to: .plan, fixLoopCap: 2, now: first)
        #expect(active.finishedAt == nil)
        let cancelled = try TaskTransitions.move(active, to: .cancelled, fixLoopCap: 2, now: first)
        #expect(cancelled.finishedAt == first)
        #expect(cancelled.with(state: .cancelled).finishedAt == first)
        #expect(cancelled.finishedAt != later)
    }

    @Test func boardFreezesElapsedAtFinishedAt() {
        var board = TaskBoard()
        let task = WorkflowModelTests.makeTask().with(state: .done).with(finishedAt: Date(timeIntervalSince1970: 30))
        _ = board.apply(task, now: Date(timeIntervalSince1970: 500))
        let row = board.rows(now: Date(timeIntervalSince1970: 900), fixLoopCap: 2)[0]
        #expect(row.elapsed == .seconds(30))
    }
}

@Suite(.timeLimit(.minutes(3)))
struct EnginePersistenceTests {
    @Test func tasksPersistAndRestoreParkedInANewEngine() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let first = try Harness(store: store)
        let id = await first.engine.submit(first.draft())
        #expect(await first.recorder.wait(.awaitingApproval))
        await first.engine.stop()
        // A second engine over the same file: the approval-waiting task survives, a running one would be parked.
        let second = try Harness(store: store)
        #expect(await second.engine.restore() == 1)
        #expect(await second.engine.task(id)?.state == .awaitingApproval)
        #expect(await second.engine.restore() == 0)
    }

    @Test func restoredNonWorktreeCodeTaskStillGetsAReviewBase() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let first = try Harness(settings: Harness.settings(useWorktree: false), store: store)
        let id = await first.engine.submit(first.draft())
        #expect(await first.recorder.wait(.awaitingApproval))
        await first.engine.stop()
        // Simulate a relaunch while Code was running: the saved task is in .code with its base commit.
        let saved = try #require(store.load().first { $0.id == id }).with(state: .code)
        #expect(saved.baseCommit == "snap456")
        store.save([saved])
        let second = try Harness(settings: Harness.settings(useWorktree: false), store: store)
        #expect(await second.engine.restore() == 1)
        try await second.engine.resume(id)
        #expect(await second.recorder.wait(.done))
        #expect(second.git.diffBases == ["snap456"])
    }

    @Test func terminalTaskPrunesItsSettingsSnapshot() async throws {
        let h = try Harness(settings: Harness.settings(cap: 7))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(await h.engine.effectiveSettings(for: id).fixLoopCap == 7)
        await h.engine.update(settings: Harness.settings(cap: 1))
        #expect(await h.engine.effectiveSettings(for: id).fixLoopCap == 7)
        await h.engine.cancel(id)
        #expect(await h.engine.effectiveSettings(for: id).fixLoopCap == 1)
        #expect(await h.engine.task(id)?.finishedAt != nil)
    }
}
