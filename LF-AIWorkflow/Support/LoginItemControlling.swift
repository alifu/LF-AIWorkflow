//
//  LoginItemControlling.swift
//  LF-AIWorkflow
//

import Foundation
import Observation
import ServiceManagement

/// Launch-at-login switch. The real one wraps `SMAppService.mainApp`; tests use a fake so no login item is ever touched.
@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Complexity: O(1) time, O(1) space
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// Drives the launch-at-login toggle; shows the system's error text and keeps the switch at the real state on failure.
@MainActor
@Observable
final class LaunchAtLoginModel {
    private(set) var isOn: Bool
    private(set) var errorMessage: String?
    @ObservationIgnored private let controller: any LoginItemControlling

    init(controller: any LoginItemControlling = SystemLoginItem()) {
        self.controller = controller
        isOn = controller.isEnabled
    }

    /// Complexity: O(1) time, O(1) space
    func set(_ enabled: Bool) {
        do {
            try controller.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = "Could not change launch at login: \(error.localizedDescription)"
        }
        isOn = controller.isEnabled
    }
}
