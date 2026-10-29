//
//  LaunchAtLoginTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var isEnabled: Bool
    var failure: (any Error)?
    private(set) var calls: [Bool] = []
    init(isEnabled: Bool = false) { self.isEnabled = isEnabled }
    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}

private struct Boom: LocalizedError { var errorDescription: String? { "denied" } }

@MainActor
@Suite struct LaunchAtLoginTests {
    @Test func startsFromTheControllerState() {
        #expect(LaunchAtLoginModel(controller: FakeLoginItem(isEnabled: true)).isOn)
    }

    @Test func togglingCallsTheController() {
        let fake = FakeLoginItem()
        let model = LaunchAtLoginModel(controller: fake)
        model.set(true)
        #expect(model.isOn && fake.calls == [true] && model.errorMessage == nil)
    }

    @Test func failureRevertsAndReportsTheError() {
        let fake = FakeLoginItem()
        fake.failure = Boom()
        let model = LaunchAtLoginModel(controller: fake)
        model.set(true)
        #expect(!model.isOn)
        #expect(model.errorMessage?.contains("denied") == true)
    }
}

@MainActor
@Suite struct AlertsSettingTests {
    @Test func alertsDefaultOnAndPersist() {
        let suite = "alerts-\(UUID().uuidString)"
        #expect(SettingsStore(suiteName: suite).alertsEnabled)
        SettingsStore(suiteName: suite).alertsEnabled = false
        #expect(SettingsStore(suiteName: suite).alertsEnabled == false)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
