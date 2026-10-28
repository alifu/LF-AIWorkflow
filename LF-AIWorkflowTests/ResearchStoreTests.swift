//
//  ResearchStoreTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct ResearchStoreTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func slugNeutralizesTraversal() {
        let s = Slug.make("../../etc/passwd")
        #expect(!s.contains("..") && !s.contains("/"))
        #expect(!s.isEmpty)
    }

    @Test func slugEmptyAndEmojiFallBackToPage() {
        #expect(Slug.make("") == "page")
        #expect(Slug.make("🔥🔥") == "page")
        #expect(Slug.make("..") == "page")
    }

    @Test func slugIsBoundedAndCharsetRestricted() {
        let s = Slug.make(String(repeating: "Hello World ", count: 20))
        #expect(s.count <= 40)
        #expect(s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") })
    }

    @Test func folderCollisionSuffixes() async throws {
        let root = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        let a = try await store.createFolder(question: "Same Q", date: date)
        let b = try await store.createFolder(question: "Same Q", date: date)
        let c = try await store.createFolder(question: "Same Q", date: date)
        #expect(a.url.lastPathComponent.hasSuffix("-same-q"))
        #expect(b.url.lastPathComponent == a.url.lastPathComponent + "-2")
        #expect(c.url.lastPathComponent == a.url.lastPathComponent + "-3")
    }

    @Test func writesAreInsideFolderWithPrivatePermissions() async throws {
        let root = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        let f = try await store.createFolder(question: "Q", date: date)
        let url = try await store.writeReport("# R", in: f)
        #expect(url.path.hasPrefix(f.url.resolvingSymlinksInPath().path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: f.url.path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
    }

    @Test func existingSymlinkTargetIsRefused() async throws {
        let root = try TestEnv.makeTempDir()
        let outside = try TestEnv.makeTempDir().appendingPathComponent("victim.md")
        let store = ResearchStore(root: root)
        let f = try await store.createFolder(question: "Q", date: date)
        try FileManager.default.createSymbolicLink(at: f.url.appendingPathComponent("report.md"), withDestinationURL: outside)
        await #expect(throws: ResearchStoreError.self) { try await store.writeReport("pwn", in: f) }
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func folderOutsideRootIsRefused() async throws {
        let root = try TestEnv.makeTempDir()
        let other = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        await #expect(throws: ResearchStoreError.self) {
            try await store.writeReport("x", in: ResearchFolder(url: other))
        }
    }

    @Test func frontMatterInjectionStaysOneField() async throws {
        let root = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        let f = try await store.createFolder(question: "Q", date: date)
        let src = ResearchSource(url: "https://e.com/a", title: "x\"\nurl: evil", body: "body")
        let url = try await store.writeSource(src, index: 1, in: f)
        let text = try String(contentsOf: url, encoding: .utf8)
        let front = text.components(separatedBy: "---\n")[1]
        #expect(front.split(separator: "\n").filter { $0.hasPrefix("url:") }.count == 1)
        #expect(front.contains("title: \"x\\\"\\nurl: evil\""))
        #expect(url.lastPathComponent.hasPrefix("01-"))
    }

    @Test func tableAndCSVAreWritten() async throws {
        let root = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        let f = try await store.createFolder(question: "Q", date: date)
        let t = try await store.writeTable([["h", "v"], ["=x", "1,2"]], source: 3, index: 2, in: f)
        #expect(t.lastPathComponent == "03-2.csv")
        #expect(try String(contentsOf: t, encoding: .utf8) == "h,v\r\n'=x,\"1,2\"\r\n")
        #expect(t.deletingLastPathComponent().resolvingSymlinksInPath() == f.url.resolvingSymlinksInPath().appendingPathComponent("tables"))
        let c = try await store.writeComparisonCSV([["h"], ["=cmd"]], in: f)
        let text = try String(contentsOf: c, encoding: .utf8)
        #expect(text.contains("'=cmd"))
    }
}
