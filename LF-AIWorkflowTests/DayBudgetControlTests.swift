//
//  DayBudgetControlTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct DayBudgetControlTests {
    @Test func dayCapControlIsReportedDisabled() {
        #expect(!DayBudgetControl.current.isEnabled)
    }

    @Test func captionIsHonestAboutNotEnforcing() {
        #expect(DayBudgetControl.current.caption == "Daily cap isn't enforced yet")
    }

    @Test func voiceOverLabelSaysUnavailableAndNotEnforced() {
        let label = DayBudgetControl.current.accessibilityLabel
        #expect(label.contains("unavailable"))
        #expect(label.contains("isn't enforced yet"))
    }
}
