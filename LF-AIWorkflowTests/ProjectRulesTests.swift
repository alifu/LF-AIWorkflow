//
//  ProjectRulesTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ProjectRulesTests {
    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func noneMeansMissingRules() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.warnings == [.missingRules])
        #expect(r.rulesFiles.isEmpty)
    }

    @Test func smallFileHasNoWarning() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try "Use tabs.\n".write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.warnings.isEmpty)
        #expect(r.rulesFiles.count == 1)
        #expect(r.rulesFiles[0].byteSize == 10)
        #expect(r.rulesFiles[0].estimatedTokens > 0)
        #expect(!r.rulesFiles[0].isTooLarge)
    }

    @Test func bothFilesListed() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for n in ProjectRules.rulesNames { try "rules".write(to: root.appendingPathComponent(n), atomically: true, encoding: .utf8) }
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.rulesFiles.map(\.url.lastPathComponent) == ["CLAUDE.md", "AGENTS.md"])
    }

    @Test func hugeFileIsTooLargeAndFast() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("AGENTS.md")
        let line = Data("This is a line of rules text for the agent to follow.\n".utf8)
        var big = Data()
        while big.count < 5 << 20 { big.append(line) }
        try big.write(to: url)
        let start = ContinuousClock.now
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(ContinuousClock.now - start < .milliseconds(100))
        #expect(r.rulesFiles.count == 1)
        #expect(r.rulesFiles[0].isTooLarge)
        #expect(r.rulesFiles[0].byteSize == UInt64(big.count))
        #expect(r.rulesFiles[0].estimatedTokens > 800)
        guard case .tooLarge(let file, let tokens, let limit)? = r.warnings.first else {
            Issue.record("expected tooLarge"); return
        }
        #expect(file == "AGENTS.md")
        #expect(tokens > 800)
        #expect(limit == 800)
        #expect(ProjectRules.sampleBytes(of: url).count == ProjectRules.readCapBytes)
    }

    @Test func onlyChecklistsPicked() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("checklist-ios.md"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("checklist-api.md"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.checklists.map(\.lastPathComponent) == ["checklist-api.md", "checklist-ios.md"])
    }

    @Test func directoryNamedClaudeMdIgnored() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("CLAUDE.md"), withIntermediateDirectories: true)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.rulesFiles.isEmpty)
        #expect(r.warnings == [.missingRules])
    }

    @Test func unreadableFileWarns() throws {
        let root = try makeRoot()
        let url = root.appendingPathComponent("CLAUDE.md")
        defer { chmod(url.path, 0o644); try? FileManager.default.removeItem(at: root) }
        try "secret".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.warnings.contains(.unreadable("CLAUDE.md")))
    }

    @Test func symlinkedRulesFileOutsideProjectIsRejected() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeRoot(); defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("CLAUDE.md")
        try "secret outside".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("CLAUDE.md"), withDestinationURL: target)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.rulesFiles.isEmpty)
        #expect(r.warnings == [.missingRules])
    }

    @Test func symlinkedChecklistOutsideProjectIsRejected() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeRoot(); defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("checklist-leak.md")
        try "leak".write(to: target, atomically: true, encoding: .utf8)
        let dir = root.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("checklist-leak.md"), withDestinationURL: target)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.checklists.isEmpty)
    }

    @Test func symlinkedRulesFileInsideProjectIsAccepted() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("docs-CLAUDE.md")
        try "inside".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("CLAUDE.md"), withDestinationURL: real)
        let r = ProjectRules.scan(root: root, rulesMaxTokens: 800)
        #expect(r.rulesFiles.map(\.url.lastPathComponent) == ["CLAUDE.md"])
    }
}
