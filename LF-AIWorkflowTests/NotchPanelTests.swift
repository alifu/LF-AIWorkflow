//
//  NotchPanelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import AppKit
@testable import LF_AIWorkflow

@MainActor
@Suite struct NotchPanelTests {
    @Test func losingKeyabilityResignsKeyStatus() {
        let panel = NotchPanel()
        panel.setKeyable(true)
        #expect(panel.canBecomeKey)
        panel.setKeyable(false)
        #expect(!panel.canBecomeKey)
        #expect(panel.resignKeyCount == 1)
    }

    @Test func stayingNonKeyableDoesNotResignRepeatedly() {
        let panel = NotchPanel()
        panel.setKeyable(false)
        #expect(panel.resignKeyCount == 0)
    }
}
