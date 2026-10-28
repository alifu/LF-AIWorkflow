//
//  TokenBudgetTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct TokenBudgetTests {
    private func usage(_ tokens: Int, cacheRead: Int = 0) -> TokenUsage {
        TokenUsage(input: tokens, output: 0, cacheRead: cacheRead, cacheCreation: 0)
    }
    private let budget = TokenBudget.default

    @Test func defaults() {
        #expect(budget.perTaskMaxTokens == 150_000)
        #expect(budget.inlineMaxTokens == 2_000)
        #expect(budget.errorMaxTokens == 1_500)
        #expect(budget.rulesMaxTokens == 800)
        #expect(budget.promptCap(for: .plan) == 4_000)
        #expect(budget.promptCap(for: .code) == 6_000)
        #expect(budget.promptCap(for: .fix) == 3_000)
        #expect(budget.promptCap(for: .review) == 12_000)
    }

    @Test func billableExcludesCacheRead() {
        let u = TokenUsage(input: 1, output: 2, cacheRead: 100, cacheCreation: 4)
        #expect(u.billableTotal == 7)
    }

    @Test func underLimitProceeds() {
        #expect(budget.check(spent: usage(100_000), nextEstimate: 1_000) == .proceed)
    }

    @Test func exactlyAtLimitProceeds() {
        #expect(budget.check(spent: usage(149_000), nextEstimate: 1_000) == .proceed)
    }

    @Test func overLimitPauses() {
        #expect(budget.check(spent: usage(150_001), nextEstimate: 0) == .pause(spent: 150_001, limit: 150_000))
    }

    @Test func estimatePushesOver() {
        #expect(budget.check(spent: usage(149_000), nextEstimate: 1_001) == .pause(spent: 149_000, limit: 150_000))
    }

    @Test func cacheReadsDoNotCount() {
        #expect(budget.check(spent: usage(10, cacheRead: 10_000_000), nextEstimate: 0) == .proceed)
    }

    @Test func raisingReturnsCopy() {
        let raised = budget.raising(by: 50_000)
        #expect(raised.perTaskMaxTokens == 200_000)
        #expect(budget.perTaskMaxTokens == 150_000)
        #expect(raised.promptMaxTokens == budget.promptMaxTokens)
    }

    @Test func nonPositiveLimitAlwaysPauses() {
        let zero = budget.raising(by: -150_000)
        #expect(zero.perTaskMaxTokens == 0)
        #expect(zero.check(spent: .zero, nextEstimate: 0) == .pause(spent: 0, limit: 0))
        let negative = budget.raising(by: -200_000)
        #expect(negative.check(spent: .zero, nextEstimate: 0) == .pause(spent: 0, limit: -50_000))
    }
}
