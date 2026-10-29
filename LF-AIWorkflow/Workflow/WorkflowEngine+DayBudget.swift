//
//  WorkflowEngine+DayBudget.swift
//  LF-AIWorkflow
//

import Foundation

extension WorkflowEngine {
    /// Parks the task (awaitingInput) when today's total plus the next prompt would pass the daily cap.
    /// The cap is read from the latest settings, so raising it in Settings and resuming continues the task.
    /// A cap of 0 or no ledger means no daily limit.
    /// Complexity: O(1) time, O(1) space
    func withinDayBudget(_ id: UUID, estimate: Int) async -> Bool {
        let limit = settings.dayBudget
        guard limit > 0, let ledger = deps.ledger else { return true }
        let spent = await ledger.used()
        guard spent + estimate > limit else { return true }
        await park(id, .dayBudgetExceeded(spent: spent, limit: limit))
        return false
    }

    /// Adds a stage's billable tokens to today's total.
    /// Complexity: O(1) time, O(1) space
    func recordDay(_ usage: TokenUsage) async {
        await deps.ledger?.add(usage.billableTotal)
    }
}
