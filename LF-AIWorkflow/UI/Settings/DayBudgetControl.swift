//
//  DayBudgetControl.swift
//  LF-AIWorkflow
//

/// What the "Per day" budget control tells the user. The daily cap is stored but not enforced (TD-066),
/// so the field is shown disabled and says so instead of implying protection that does not exist.
nonisolated struct DayBudgetControl: Sendable, Equatable {
    let isEnabled: Bool
    let label: String
    let caption: String
    let accessibilityLabel: String

    static let current = DayBudgetControl(
        isEnabled: false,
        label: "Per day",
        caption: "Daily cap isn't enforced yet",
        accessibilityLabel: "Per day token cap, unavailable. Daily cap isn't enforced yet")
}
