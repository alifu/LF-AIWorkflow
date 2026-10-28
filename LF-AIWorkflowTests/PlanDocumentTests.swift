//
//  PlanDocumentTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct PlanDocumentTests {
    private let path = URL(fileURLWithPath: "/tmp/plan.md")
    private func parse(_ text: String) -> PlanDocument { PlanDocument.parse(text, path: path) }

    @Test func numberedList() {
        let doc = parse("# Plan\n\n1. Add the model\n2) Wire the view\n3. Test it\n")
        #expect(doc.steps == ["Add the model", "Wire the view", "Test it"])
    }

    @Test func checklist() {
        let doc = parse("- [ ] First\n- [x] Second\n* [X] Third\n- not a step\n")
        #expect(doc.steps == ["First", "Second", "Third"])
    }

    @Test func stepHeadingsWinOverNestedItems() {
        let doc = parse("## Step 1: Models\n1. detail a\n2. detail b\n## Step 2: Views\n- [ ] detail c\n## Notes\nignore\n")
        #expect(doc.steps == ["Step 1: Models", "Step 2: Views"])
    }

    @Test func nestedItemsAreNotSteps() {
        let doc = parse("1. Top\n    1. nested\n2. Next\n")
        #expect(doc.steps == ["Top", "Next"])
    }

    @Test func crlfAndTabs() {
        let doc = parse("1. One\r\n2. Two\r\n\r\n")
        #expect(doc.steps == ["One", "Two"])
    }

    @Test func emptyAndProseOnly() {
        #expect(parse("").steps.isEmpty)
        #expect(parse("   \n\n").steps.isEmpty)
        #expect(parse("Just a paragraph.\nAnother.").steps.isEmpty)
    }

    @Test func estimatesTokensFromTheWholeText() {
        let text = String(repeating: "word ", count: 400)
        #expect(parse(text).estimatedTokens == TokenEstimator.estimate(text))
        #expect(parse(text).estimatedTokens > 0)
    }

    @Test func loadReadsAFile() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, "p.md", "1. A\n2. B\n")
        let doc = try await PlanDocument.load(dir.appendingPathComponent("p.md"))
        #expect(doc.steps == ["A", "B"])
        #expect(!doc.isTruncated)
    }

    @Test func loadCapsHugeFiles() async throws {
        let dir = try TestEnv.makeTempDir()
        let line = "1. step\n"
        try TestEnv.write(dir, "p.md", String(repeating: line, count: (PlanDocument.maxBytes / line.utf8.count) * 3))
        let doc = try await PlanDocument.load(dir.appendingPathComponent("p.md"))
        #expect(doc.isTruncated)
        #expect(doc.steps.count <= PlanDocument.maxBytes / line.utf8.count + 1)
        #expect(doc.steps.count > 1000)
    }

    @Test func loadMissingFileThrows() async {
        await #expect(throws: (any Error).self) { try await PlanDocument.load(URL(fileURLWithPath: "/nonexistent/plan.md")) }
    }
}
