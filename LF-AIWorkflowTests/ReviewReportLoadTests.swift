//
//  ReviewReportLoadTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct ReviewReportLoadTests {
    private let sample = ReviewReport(findings: [
        Finding(severity: .high, file: "Theme.kt", line: 31, issue: "Hardcoded color", suggestion: "Use the token"),
        Finding(severity: .medium, file: "src/Net.swift", line: nil, issue: "No timeout", suggestion: nil),
        Finding(severity: .low, file: "a.swift", line: 2, issue: "Naming", suggestion: nil),
    ], unparsedLineCount: 0)

    @Test func roundTripsMarkdown() {
        let loaded = ReviewReport.parseSaved(sample.markdown(title: "login"))
        #expect(loaded == sample)
    }

    @Test func roundTripKeepsTheUnparsedCount() {
        let report = ReviewReport(findings: sample.findings, unparsedLineCount: 2)
        #expect(ReviewReport.parseSaved(report.markdown(title: "x")) == report)
    }

    @Test func emptyReport() {
        let report = ReviewReport(findings: [], unparsedLineCount: 0)
        #expect(ReviewReport.parseSaved(report.markdown(title: "x")) == report)
    }

    @Test func malformedSavedLinesCountAsUnparsed() {
        let text = "# Review: x\n\n- **HIGH** `a.swift:1` - fine\n- **WAT** `b.swift:2` - bad severity\n- **LOW** `` - no file\n- **MEDIUM**\nrandom prose\n"
        let loaded = ReviewReport.parseSaved(text)
        #expect(loaded.findings.map(\.file) == ["a.swift"])
        #expect(loaded.unparsedLineCount == 3)
    }

    @Test func acceptsBracketLinesToo() {
        let loaded = ReviewReport.parseSaved("[HIGH] a.swift:9 - broken - fix it\n")
        #expect(loaded.findings == [Finding(severity: .high, file: "a.swift", line: 9, issue: "broken", suggestion: "fix it")])
    }

    @Test func suggestionWithoutAFindingIsIgnored() {
        let loaded = ReviewReport.parseSaved("  - Suggestion: orphan\n- **LOW** `a:1` - x\n")
        #expect(loaded.findings.count == 1)
        #expect(loaded.findings[0].suggestion == nil)
    }

    @Test func loadReadsASavedFile() async throws {
        let root = try TestEnv.makeTempDir()
        let url = try sample.save(projectRoot: root, slug: "login")
        #expect(try await ReviewReport.load(markdownAt: url).findings == sample.findings)
    }

    @Test func loadMissingFileThrows() async {
        await #expect(throws: (any Error).self) { try await ReviewReport.load(markdownAt: URL(fileURLWithPath: "/nonexistent/r.md")) }
    }

    @Test func loadIsBoundedInSizeAndFindingCount() async throws {
        let root = try TestEnv.makeTempDir()
        let many = (0..<5_000).map { "- **LOW** `f\($0).swift:1` - issue \($0)\n" }.joined()
        try TestEnv.write(root, "r.md", many)
        let loaded = try await ReviewReport.load(markdownAt: root.appendingPathComponent("r.md"))
        #expect(loaded.findings.count == ReviewReport.maxLoadedFindings)
    }

    @Test func binaryGarbageDoesNotCrash() async throws {
        let root = try TestEnv.makeTempDir()
        try Data((0..<2000).map { UInt8($0 % 256) }).write(to: root.appendingPathComponent("r.md"))
        _ = try await ReviewReport.load(markdownAt: root.appendingPathComponent("r.md"))
    }
}
