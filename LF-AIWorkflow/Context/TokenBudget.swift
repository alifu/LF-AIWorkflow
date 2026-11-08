//
//  TokenBudget.swift
//  LF-AIWorkflow
//

nonisolated struct TokenBudget: Sendable, Equatable {
    let perTaskMaxTokens: Int
    let inlineMaxTokens: Int
    let errorMaxTokens: Int
    let rulesMaxTokens: Int
    let promptMaxTokens: [WorkflowStage: Int]

    static let `default` = TokenBudget(perTaskMaxTokens: 150_000, inlineMaxTokens: 2_000, errorMaxTokens: 1_500,
                                       rulesMaxTokens: 800,
                                       promptMaxTokens: [.plan: 4_000, .code: 6_000, .fix: 3_000, .review: 12_000])

    enum Decision: Sendable, Equatable { case proceed, pause(spent: Int, limit: Int) }

    /// Pauses when billable spend plus the next prompt would exceed the per-task limit.
    /// Complexity: O(1) time, O(1) space
    func check(spent: TokenUsage, nextEstimate: Int) -> Decision {
        let total = spent.billableTotal
        guard perTaskMaxTokens > 0, total + max(0, nextEstimate) <= perTaskMaxTokens else {
            return .pause(spent: total, limit: perTaskMaxTokens)
        }
        return .proceed
    }

    /// Complexity: O(s) time, O(s) space (s = stages)
    func raising(by tokens: Int) -> TokenBudget {
        TokenBudget(perTaskMaxTokens: perTaskMaxTokens + tokens, inlineMaxTokens: inlineMaxTokens,
                    errorMaxTokens: errorMaxTokens, rulesMaxTokens: rulesMaxTokens, promptMaxTokens: promptMaxTokens)
    }

    /// Complexity: O(1) time, O(1) space
    func promptCap(for stage: WorkflowStage) -> Int { promptMaxTokens[stage] ?? 0 }
}
