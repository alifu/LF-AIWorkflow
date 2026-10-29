//
//  ResearchTaskStoreTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

/// Research task persistence (TD-093).
struct ResearchTaskStoreTests {
    private func store() throws -> (ResearchTaskStore, URL) {
        let dir = try TestEnv.makeTempDir()
        return (ResearchTaskStore(fileURL: dir.appendingPathComponent("sub/research.json")), dir)
    }

    private func rich() -> ResearchTask {
        ResearchTask(question: "q?", output: .comparison, deep: true, state: .done,
                     folder: ResearchFolder(url: URL(fileURLWithPath: "/r/2026-01-01-q", isDirectory: true)), sessionId: "s",
                     tokensUsed: 42, errorMessage: "e", denials: ["Bash"],
                     reportFile: URL(fileURLWithPath: "/r/2026-01-01-q/report.md"))
    }

    @Test func saveThenLoadRoundTripsMetadata() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = rich()
        store.save([task])
        #expect(store.load() == [task])
    }

    @Test func previewIsNotPersisted() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let preview = SourcesPreview(rows: [], removedLines: 1, totalTokens: 9)
        store.save([rich().with(preview: preview)])
        #expect(store.load().first?.preview == nil)
    }

    @Test func missingCorruptOrUnknownVersionLoadsEmpty() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.load().isEmpty)
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
        try Data(#"{"version":99,"tasks":[]}"#.utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test func corruptOrUnknownVersionFileIsBackedUpBeforeASave() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"version":99,"tasks":[]}"#.utf8)
        try original.write(to: store.fileURL)
        #expect(store.load().isEmpty)
        store.save([rich()])
        let backups = FileBackup.backups(of: store.fileURL)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(store.load().count == 1)
    }

    @Test func droppedUnknownRecordsArePreservedInABackup() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.save([rich()])
        var text = try String(contentsOf: store.fileURL, encoding: .utf8)
        text = text.replacingOccurrences(of: #""output":"comparison""#, with: #""output":"hologram""#)
        try Data(text.utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
        store.save([])
        let backups = FileBackup.backups(of: store.fileURL)
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0], encoding: .utf8).contains("hologram"))
    }

    @Test func finishedTasksAreCappedKeepingNewestAndLive() throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let finished = (0..<(ResearchTaskStore.maxFinished + 5)).map { _ in rich() }
        let live = ResearchTask(question: "live", output: .summary, deep: false, state: .awaitingPreview)
        store.save([live] + finished)
        let loaded = store.load()
        #expect(loaded.filter { $0.state == .done }.count == ResearchTaskStore.maxFinished)
        #expect(loaded.contains { $0.id == live.id })
        #expect(loaded.contains { $0.id == finished.last?.id })
        #expect(!loaded.contains { $0.id == finished.first?.id })
    }

    @Test func restoreMarksInFlightTasksFailedAndKeepsFinished() {
        let done = rich()
        let mid = ResearchTask(question: "m", output: .summary, deep: false, state: .analyze)
        let waiting = ResearchTask(question: "w", output: .summary, deep: false, state: .awaitingPreview)
        let restored = ResearchRestore.apply([done, mid, waiting])
        #expect(restored[0] == done)
        #expect(restored[1].state == .failed)
        #expect(restored[1].errorMessage == ResearchRestore.interruptedMessage)
        #expect(restored[2].state == .failed)
    }

    @Test func pipelineRestoresAndPersistsTasks() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.save([rich(), ResearchTask(question: "m", output: .summary, deep: false, state: .clean)])
        let pipeline = ResearchPipeline(deps: ResearchTaskStoreTests.deps(dir), settings: ResearchSettings(), persistence: store)
        await pipeline.restore()
        let states = store.load().map(\.state)
        #expect(states == [.done, .failed])
        let id = try #require(store.load().first?.id)
        #expect(await pipeline.task(id)?.state == .done)
    }

    private static func deps(_ dir: URL) -> ResearchDependencies {
        ResearchDependencies(
            safari: UnavailableSafari(), crawler: NoCrawler(), runner: NoRunner(), store: ResearchStore(root: dir),
            now: { Date() }, dayTokensUsed: { 0 })
    }
}

private struct NoCrawler: ResearchCrawling {
    func crawl(start: [URL], limits: CrawlLimits) -> AsyncThrowingStream<CrawlEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct NoRunner: ResearchClaudeRunning {
    func run(_ request: ResearchRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
