//
//  WorkflowEngine+DayBudget.swift
//  LF-AIWorkflow
//

import Foundation

extension WorkflowEngine {
    /// Reserves the next prompt's estimate against today's cap; parks the task (awaitingInput) when it would not fit.
    /// The cap is read from the latest settings, so raising it in Settings and resuming continues the task.
    /// A cap of 0 or no ledger means no daily limit and nothing is reserved.
    /// Returns the reserved amount (0 when unlimited), or nil when parked. Settle it with `settleDay`.
    /// Complexity: O(1) time, O(1) space
    func reserveDayBudget(_ id: UUID, estimate: Int) async -> Int? {
        let limit = settings.dayBudget
        guard limit > 0, let ledger = deps.ledger else { return 0 }
        switch await ledger.reserve(estimate, limit: limit) {
        case .granted: return max(0, estimate)
        case .denied(let spent):
            await park(id, .dayBudgetExceeded(spent: spent, limit: limit))
            return nil
        }
    }

    /// Replaces a stage's reservation with its billable tokens in today's total.
    /// With no daily cap (`reserved == 0`) this is a plain add.
    /// Complexity: O(1) time, O(1) space
    func settleDay(reserved: Int, usage: TokenUsage) async {
        await deps.ledger?.settle(reserved: reserved, actual: usage.billableTotal)
    }
}
