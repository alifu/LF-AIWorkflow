import Foundation
import Testing
@testable import LF_AIWorkflow

struct SafeProjectFileTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesUnderRealDirectory() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try SafeProjectFile.write("hi", to: ".claude/plans", name: "a.md", root: root)
        #expect(try String(contentsOf: url, encoding: .utf8) == "hi")
    }

    @Test func symlinkedLeafDirectoryIsRefused() throws {
        let root = try tempDir()
        let outside = try tempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".claude/plans"), withDestinationURL: outside)
        #expect(throws: SafeProjectFile.Failure.self) {
            try SafeProjectFile.write("x", to: ".claude/plans", name: "a.md", root: root)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: outside.path))?.isEmpty == true)
    }

    @Test func symlinkedClaudeDirectoryIsRefused() throws {
        let root = try tempDir()
        let outside = try tempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".claude"), withDestinationURL: outside)
        #expect(throws: SafeProjectFile.Failure.self) {
            try SafeProjectFile.write("x", to: ".claude/reviews", name: "a.md", root: root)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: outside.path))?.isEmpty == true)
    }

    @Test func symlinkedTargetFileIsReplacedNotFollowed() throws {
        let root = try tempDir()
        let outside = try tempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let dir = root.appendingPathComponent(".claude/plans")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let victim = outside.appendingPathComponent("victim.txt")
        try "orig".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("a.md"), withDestinationURL: victim)
        _ = try? SafeProjectFile.write("new", to: ".claude/plans", name: "a.md", root: root)
        #expect(try String(contentsOf: victim, encoding: .utf8) == "orig")
    }

    @Test func slugTransliteratesNonAscii() {
        let jp = WorktreeManager.slug(for: "日本語")
        let cafe = WorktreeManager.slug(for: "café")
        #expect(jp != "task" && !jp.isEmpty)
        #expect(cafe == "cafe")
        #expect(jp != cafe)
    }

    @Test func uniqueFileStemsDifferForSameSlug() {
        let a = SafeProjectFile.stem(slug: "fix", id: UUID())
        let b = SafeProjectFile.stem(slug: "fix", id: UUID())
        #expect(a != b)
        #expect(a.hasPrefix("fix-"))
    }
}
