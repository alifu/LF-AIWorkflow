//
//  TechDebtH3Tests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(2)))
struct TechDebtH3Tests {
    private let planFile = URL(fileURLWithPath: "/work/plans/plan-x.md")

    private func client() -> GitClient {
        GitClient(locator: ToolLocator(searchPath: ["/usr/bin"]), timeout: .seconds(30), environment: TestEnv.git)
    }

    // MARK: TD-034

    @Test func tinyPromptCapClampsThePromptToTheCap() {
        let tiny = TokenBudget(perTaskMaxTokens: 150_000, inlineMaxTokens: 2_000, errorMaxTokens: 1_500,
                               rulesMaxTokens: 800, promptMaxTokens: [.plan: 20, .code: 20])
        for stage in [WorkflowStage.plan, .code] {
            let task = WorkflowModelTests.makeTask().with(planFile: planFile)
            let input = StageContextInput(stage: stage, task: task, documents: [], sentHashes: [], graph: .empty,
                                          diff: nil, errors: nil, checklists: [], findingsForFix: [])
            let built = ContextBuilder.build(input, budget: tiny)
            #expect(built.estimatedTokens <= 20)
            #expect(TokenEstimator.estimate(built.text) == built.estimatedTokens)
        }
    }

    @Test func clampedPromptNeverListsFilesItNoLongerContains() {
        let tiny = TokenBudget(perTaskMaxTokens: 150_000, inlineMaxTokens: 2_000, errorMaxTokens: 1_500,
                               rulesMaxTokens: 800, promptMaxTokens: [.plan: 20])
        let file = ContextDocument(url: URL(fileURLWithPath: "/outside/spec.md"), byteSize: 10_000, hash: 7, text: nil)
        let task = WorkflowModelTests.makeTask().with(planFile: planFile)
        let input = StageContextInput(stage: .plan, task: task, documents: [file], sentHashes: [], graph: .empty,
                                      diff: nil, errors: nil, checklists: [], findingsForFix: [])
        let built = ContextBuilder.build(input, budget: tiny)
        #expect(built.readFiles.allSatisfy { built.text.contains($0.path) })
        #expect(built.sentHashes.isEmpty || built.text.contains("/outside/spec.md"))
    }

    // MARK: TD-109

    @Test func reviewExcludesCoverThePlanFolder() {
        #expect(GitClient.reviewExcludes.contains(":(exclude,glob).claude/plans/**"))
    }

    @Test func planFileIsExcludedFromReviewDiffWithMarking() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "a.swift", "let a = 2\n")
        try TestEnv.write(repo, ".claude/plans/login-x.md", "PLAN BODY MARKER\n")
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: true)
        #expect(diff.contains("+let a = 2"))
        #expect(!diff.contains("PLAN BODY MARKER"))
        #expect(!diff.contains("login-x.md"))
    }

    @Test func planFileIsExcludedFromReviewDiffWithoutMarking() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "a.swift", "let a = 2\n")
        try TestEnv.write(repo, ".claude/plans/login-x.md", "PLAN BODY MARKER\n")
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: false)
        #expect(diff.contains("+let a = 2"))
        #expect(!diff.contains("PLAN BODY MARKER"))
    }
}
