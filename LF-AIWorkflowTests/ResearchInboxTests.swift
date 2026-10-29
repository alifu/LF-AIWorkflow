//
//  ResearchInboxTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct ResearchInboxTests {
    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
    }

    private func page(_ url: String, title: String = "T") -> CapturedPage {
        CapturedPage(title: title, url: URLNormalizer.normalize(url)!, text: "body of \(url)", headings: [], links: [],
                     tables: [], hasPasswordField: false)
    }

    @Test func addThenItemsPersistsAcrossInstances() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = ResearchInbox(folder: folder)
        #expect(try await first.add(page("https://a.example/x")) == .added(count: 1))
        let second = ResearchInbox(folder: folder)
        let items = try await second.items()
        #expect(items.count == 1)
        #expect(items[0].page.url.absoluteString == "https://a.example/x")
        #expect(items[0].page.text == "body of https://a.example/x")
    }

    @Test func duplicateVariantsAreSkipped() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ResearchInbox(folder: folder)
        _ = try await inbox.add(page("https://a.example/x"))
        #expect(try await inbox.add(page("https://a.example/x?utm_source=n#frag")) == .duplicate)
        #expect(try await inbox.items().count == 1)
    }

    @Test func capDropsOldestAndReportsIt() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ResearchInbox(folder: folder, cap: 3)
        for i in 0..<3 { _ = try await inbox.add(page("https://a.example/\(i)")) }
        let result = try await inbox.add(page("https://a.example/3"))
        #expect(result == .addedDroppingOldest(count: 3, dropped: 1))
        let urls = try await inbox.items().map(\.page.url.path)
        #expect(urls == ["/1", "/2", "/3"])
    }

    @Test func removeDeletesOneItem() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ResearchInbox(folder: folder)
        _ = try await inbox.add(page("https://a.example/1"))
        _ = try await inbox.add(page("https://a.example/2"))
        let first = try await inbox.items()[0]
        try await inbox.remove(first.id)
        #expect(try await inbox.items().map(\.page.url.path) == ["/2"])
    }

    @Test func drainReturnsAllAndEmpties() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ResearchInbox(folder: folder)
        _ = try await inbox.add(page("https://a.example/1"))
        _ = try await inbox.add(page("https://a.example/2"))
        #expect(try await inbox.drain().count == 2)
        #expect(try await inbox.items().isEmpty)
        #expect(try await ResearchInbox(folder: folder).items().isEmpty)
    }

    @Test func traversalEntryNameIsIgnoredAndNeverTouched() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dir = folder.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let victim = folder.appendingPathComponent("victim.json")
        let pageJSON = #"{"title":"x","url":"https://a.example/x","text":"t","headings":[],"links":[],"tables":[],"hasPasswordField":false}"#
        try Data(pageJSON.utf8).write(to: victim)
        let id = UUID()
        let index = #"{"next":2,"entries":[{"id":"\#(id.uuidString)","key":"https://a.example/x","file":"../victim.json"}]}"#
        try Data(index.utf8).write(to: dir.appendingPathComponent("index.json"))
        let inbox = ResearchInbox(folder: folder)
        #expect(try await inbox.items().isEmpty)
        try await inbox.remove(id)
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test func corruptIndexIsRenamedAndRestartsEmpty() async throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dir = folder.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let inbox = ResearchInbox(folder: folder)
        #expect(try await inbox.items().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("index.json.corrupt-") })
        #expect(try await inbox.add(page("https://a.example/1")) == .added(count: 1))
    }
}
