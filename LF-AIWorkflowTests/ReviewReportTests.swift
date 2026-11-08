//
//  ReviewReportTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ReviewReportTests {
    private func fixture(_ name: String) throws -> String { String(decoding: try loadFixture(name), as: UTF8.self) }

    @Test func mixedFixtureOrderAndCount() throws {
        let r = ReviewReport.parse(try fixture("review_output_mixed.txt"))
        #expect(r.findings.count == 7)
        #expect(r.unparsedLineCount == 1)
        let keys = r.findings.map { "\($0.severity)|\($0.file)|\($0.line.map(String.init) ?? "-")" }
        #expect(keys == [
            "critical|Sources/a.swift|10",
            "high|Sources/My File.swift|7",
            "high|Sources/a.swift|20",
            "medium|Sources/a.swift|3",
            "medium|Sources/a.swift|3",
            "low|Sources/b.swift|40",
            "info|README.md|-",
        ])
        #expect(r.findings[0].issue == "force unwrap crashes on nil")
        #expect(r.findings[0].suggestion == "use guard let")
        #expect(r.findings[3].issue == "long function")
        #expect(r.findings[3].suggestion == nil)
        #expect(r.findings[4].issue == "second issue at same spot")
        #expect(r.findings[1].suggestion == "propagate the error")
    }

    @Test func noFindings() throws {
        let r = ReviewReport.parse(try fixture("review_output_none.txt"))
        #expect(r.findings.isEmpty)
        #expect(r.unparsedLineCount == 0)
    }

    @Test func lowerCaseAndMed() {
        let r = ReviewReport.parse("[med] a.swift:1 - x\n[Low] b.swift:2 - y\n")
        #expect(r.findings.map(\.severity) == [.medium, .low])
    }

    @Test func emDashSeparators() {
        let r = ReviewReport.parse("[HIGH] a.swift:1 — bad thing — fix it")
        #expect(r.findings.first?.issue == "bad thing")
        #expect(r.findings.first?.suggestion == "fix it")
    }

    @Test func unknownSeverityCountsAsUnparsed() {
        let r = ReviewReport.parse("[BLOCKER] a.swift:1 - nope")
        #expect(r.findings.isEmpty)
        #expect(r.unparsedLineCount == 1)
    }

    @Test func stableForEqualKeys() {
        let r = ReviewReport.parse("[LOW] a.swift:1 - first\n[LOW] a.swift:1 - second\n[LOW] a.swift:1 - third")
        #expect(r.findings.map(\.issue) == ["first", "second", "third"])
    }

    @Test func saveWritesUnderRootAndOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let r1 = ReviewReport.parse("[HIGH] a.swift:1 - one - fix")
        let url = try r1.save(projectRoot: root, slug: "feat-x")
        #expect(url.path == root.appendingPathComponent(".claude/reviews/feat-x.md").path)
        let first = try String(contentsOf: url, encoding: .utf8)
        #expect(first.contains("one"))
        let r2 = ReviewReport.parse("[LOW] b.swift:2 - two")
        _ = try r2.save(projectRoot: root, slug: "feat-x")
        let second = try String(contentsOf: url, encoding: .utf8)
        #expect(second.contains("two"))
        #expect(!second.contains("one"))
    }

    @Test func markdownHasTitleAndFindings() {
        let md = ReviewReport.parse("[HIGH] a.swift:1 - one - fix").markdown(title: "My task")
        #expect(md.contains("My task"))
        #expect(md.contains("a.swift:1"))
        #expect(md.contains("one"))
    }

    @Test func badSlugThrows() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let r = ReviewReport.parse("")
        for slug in ["../evil", "a/b", "", "..", ".hidden"] {
            #expect(throws: (any Error).self) { try r.save(projectRoot: root, slug: slug) }
        }
        #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("evil.md").path))
    }
}
