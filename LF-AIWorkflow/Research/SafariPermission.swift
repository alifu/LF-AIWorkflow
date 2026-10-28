//
//  SafariPermission.swift
//  LF-AIWorkflow
//

import ApplicationServices
import Foundation

nonisolated enum SafariPermissionState: Sendable, Equatable {
    case granted, denied, notDetermined, safariNotRunning
}

nonisolated enum SafariPermission {
    static let safariBundleID = "com.apple.Safari"

    /// Asks TCC without prompting (`askUserIfNeeded: false`); `Self.state(forStatus:)` maps the result.
    /// Complexity: O(1) time, O(1) space
    static func current() -> SafariPermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: safariBundleID)
        guard let desc = target.aeDesc else { return .safariNotRunning }
        return state(forStatus: AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false))
    }

    /// Complexity: O(1) time, O(1) space
    static func state(forStatus status: OSStatus) -> SafariPermissionState {
        switch status {
        case 0: .granted
        case -1743: .denied
        case -1744: .notDetermined
        default: .safariNotRunning
        }
    }
}
