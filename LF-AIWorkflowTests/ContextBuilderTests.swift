//
//  ContextBuilderTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ContextBuilderTests {
    private let budget = TokenBudget.default
    private let planFile = URL(fileURLWithPath: "/work/plans/plan-x.md")

    private func input(_ stage: WorkflowStage, documents: [ContextDocument] = [], sent: Set<UInt64> = [],
                       graph: GraphContext = .empty, diff: String? = nil, errors: String? = nil,
                       checklists: [String] = [], findings: [Finding] = []) -> StageContextInput {
        let task = WorkflowModelTests.makeTask().with(planFile: planFile)
        return StageContextInput(stage: stage, task: task, documents: documents, sentHashes: sent, graph: graph,
                                 diff: diff, errors: errors, checklists: checklists, findingsForFix: findings)
    }

    private let graph = GraphContext(text: "NODE GraphSecret [src=g.swift loc=L1]", nodes: [])

    private func doc(_ name: String, hash: UInt64?, text: String?, size: UInt64 = 100) -> ContextDocument {
        ContextDocument(url: URL(fileURLWithPath: "/docs/\(name)"), byteSize: size, hash: hash, text: text)
    }

    private func fileDiff(_ path: String, lines: Int) -> String {
        "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n@@ -1 +1 @@\n"
            + (0..<lines).map { "+let value\($0) = \($0) // generated text to take tokens\n" }.joined()
    }

    // MARK: stages

    @Test func planPromptAsksForPlanOnlyAndInlinesSmallDocs() {
        let d = doc("spec.md", hash: 1, text: "SPEC BODY")
        let built = ContextBuilder.build(input(.plan, documents: [d]), budget: budget)
        #expect(built.text.contains(WorkflowModelTests.makeTask().prompt))
        #expect(built.text.localizedCaseInsensitiveContains("plan only"))
        #expect(built.text.contains("SPEC BODY"))
        #expect(built.sentHashes == [1])
        #expect(built.addDirs.isEmpty)
    }

    @Test func codePromptHasPlanPathNotPlanText() throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("plan.md")
        try "PLAN BODY SECRET".write(to: file, atomically: true, encoding: .utf8)
        let task = WorkflowModelTests.makeTask().with(planFile: file)
        let i = StageContextInput(stage: .code, task: task, documents: [], sentHashes: [], graph: graph, diff: nil,
                                  errors: nil, checklists: [], findingsForFix: [])
        let built = ContextBuilder.build(i, budget: budget)
        #expect(built.text.contains(file.path))
        #expect(!built.text.contains("PLAN BODY SECRET"))
        #expect(built.text.contains("GraphSecret"))
    }

    @Test func reviewPromptHasNoGraphAndNoPlan() {
        let built = ContextBuilder.build(
            input(.review, graph: graph, diff: fileDiff("a.swift", lines: 2), checklists: ["CHECKLIST ITEM"]), budget: budget)
        #expect(!built.text.contains("GraphSecret"))
        #expect(!built.text.contains(planFile.path))
        #expect(built.text.contains("a.swift"))
        #expect(built.text.contains("CHECKLIST ITEM"))
        #expect(built.text.contains("[severity] file:line - issue - suggestion"))
    }

    @Test func fixPromptNeverExceedsCapEvenWithHugeErrors() {
        let huge = String(repeating: "Foo.swift:3: error: something broke here\n", count: 25_000)
        let finding = Finding(severity: .high, file: "a.swift", line: 4, issue: "bad", suggestion: "fix it")
        let built = ContextBuilder.build(input(.fix, graph: graph, errors: huge, findings: [finding]), budget: budget)
        #expect(built.estimatedTokens <= budget.promptCap(for: .fix))
        #expect(TokenEstimator.estimate(built.text) <= budget.promptCap(for: .fix))
        #expect(built.text.contains("error: something broke"))
        #expect(built.text.contains("a.swift:4"))
        #expect(!built.text.contains(planFile.path))
    }

    @Test func emptyGraphHasNoGraphHeading() {
        let built = ContextBuilder.build(input(.code, graph: .empty), budget: budget)
        #expect(!built.text.localizedCaseInsensitiveContains("graph"))
    }

    // MARK: documents

    @Test func oversizedDocumentIsListedWithItsDirectoryNotInlined() {
        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 2_000)
        let built = ContextBuilder.build(input(.plan, documents: [doc("big.md", hash: 7, text: big)]), budget: budget)
        #expect(built.text.contains("/docs/big.md"))
        #expect(!built.text.contains("lorem ipsum"))
        #expect(built.addDirs.map(\.path) == ["/docs"])
    }

    @Test func documentWithoutTextIsListedByPath() {
        let built = ContextBuilder.build(input(.plan, documents: [doc("raw.bin", hash: 8, text: nil)]), budget: budget)
        #expect(built.text.contains("/docs/raw.bin"))
        #expect(built.addDirs.map(\.path) == ["/docs"])
    }

    @Test func duplicateHashIsOmittedOnce() {
        let a = doc("a.md", hash: 5, text: "AAA")
        let b = doc("b.md", hash: 5, text: "BBB")
        let built = ContextBuilder.build(input(.plan, documents: [a, b]), budget: budget)
        #expect(built.text.contains("AAA"))
        #expect(!built.text.contains("BBB"))
        #expect(built.omitted == ["/docs/b.md"])
    }

    @Test func alreadySentHashIsOmitted() {
        let built = ContextBuilder.build(input(.code, documents: [doc("a.md", hash: 9, text: "AAA")], sent: [9]), budget: budget)
        #expect(!built.text.contains("AAA"))
        #expect(built.omitted == ["/docs/a.md"])
        #expect(built.sentHashes == [9])
    }

    // MARK: review diff

    @Test func diffOverCapKeepsSmallestFilesAndListsTheRest() {
        let tight = TokenBudget(perTaskMaxTokens: 150_000, inlineMaxTokens: 2_000, errorMaxTokens: 1_500,
                                rulesMaxTokens: 800, promptMaxTokens: [.review: 600])
        let diff = fileDiff("small.swift", lines: 3) + fileDiff("medium.swift", lines: 20) + fileDiff("large.swift", lines: 400)
        let built = ContextBuilder.build(input(.review, diff: diff), budget: tight)
        #expect(built.text.contains("+let value1 = 1 // generated"))
        #expect(built.text.contains("small.swift"))
        #expect(built.omitted.contains("large.swift"))
        #expect(built.text.contains("large.swift"))   // listed so Review can Read it
        #expect(!built.text.contains("+let value399"))
        #expect(built.estimatedTokens <= 600)
    }

    @Test func diffThatFitsIsKeptWhole() {
        let diff = fileDiff("a.swift", lines: 2) + fileDiff("b.swift", lines: 2)
        let built = ContextBuilder.build(input(.review, diff: diff), budget: budget)
        #expect(built.omitted.isEmpty)
        #expect(built.text.contains("a.swift") && built.text.contains("b.swift"))
    }

    @Test func estimatedTokensMatchesEstimator() {
        let built = ContextBuilder.build(input(.code, graph: graph), budget: budget)
        #expect(built.estimatedTokens == TokenEstimator.estimate(built.text))
    }

    // MARK: helpers

    @Test func splitDiffByFileSplitsOnDiffHeaders() {
        let parts = ContextBuilder.splitDiffByFile(fileDiff("x/a.swift", lines: 1) + fileDiff("b.swift", lines: 2))
        #expect(parts.map(\.path) == ["x/a.swift", "b.swift"])
        #expect(parts[0].text.hasPrefix("diff --git a/x/a.swift"))
        #expect(!parts[0].text.contains("b.swift"))
        #expect(ContextBuilder.splitDiffByFile("").isEmpty)
    }

    @Test func errorSymbolsDedupAndCap() {
        let errors = """
        /Users/x/App/Foo.swift:12:5: error: a
        /Users/x/App/Foo.swift:20:1: error: b
        Bar.swift:3: error: c
        src/Baz.ts:9:1 - error
        Qux.c:1: error: d
        """
        #expect(ContextBuilder.errorSymbols(errors) == ["Foo.swift", "Bar.swift", "Baz.ts"])
        #expect(ContextBuilder.errorSymbols(errors, limit: 1) == ["Foo.swift"])
        #expect(ContextBuilder.errorSymbols("no refs here").isEmpty)
    }

    @Test(arguments: WorkflowStage.allCases) func hugeTitleAndChecklistsStayWithinCap(stage: WorkflowStage) {
        let task = WorkflowModelTests.makeTask().with(planFile: planFile)
        let huge = WorkflowTask(id: task.id, title: String(repeating: "T", count: 200_000), slug: task.slug,
                                prompt: task.prompt, projectRoot: task.projectRoot, documents: [], skillDirs: [],
                                state: task.state, resumeState: nil, waitReason: nil, failure: nil, worktree: nil,
                                sessionId: nil, planFile: planFile, fixAttempts: 0, usageByStage: [:],
                                lastErrors: nil, testCommandDisplay: nil, reviewFile: nil, createdAt: task.createdAt)
        let checklists = (0..<60).map { _ in String(repeating: "check this item carefully\n", count: 300) }
        let i = StageContextInput(stage: stage, task: huge, documents: [], sentHashes: [], graph: .empty,
                                  diff: fileDiff("a.swift", lines: 50), errors: "e.swift:1: error: x",
                                  checklists: stage == .review ? checklists : [], findingsForFix: [])
        let built = ContextBuilder.build(i, budget: budget)
        #expect(built.estimatedTokens <= budget.promptCap(for: stage), "\(stage) prompt over cap")
    }
}
