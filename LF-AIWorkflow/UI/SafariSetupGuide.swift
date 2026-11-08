//
//  SafariSetupGuide.swift
//  LF-AIWorkflow
//

import Foundation

/// What the Safari setup sheet tells the user, derived from the permission state and the last Safari error.
nonisolated struct SafariSetupGuide: Sendable, Equatable {
    let title: String
    let steps: [String]
    let showsOpenSettings: Bool
    let fallback: String

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    private static let fallbackText = "Or skip Safari: add URLs and crawl public URLs only."

    /// nil when Safari works.
    /// Complexity: O(1) time, O(1) space
    static func make(state: SafariPermissionState, error: SafariError?) -> SafariSetupGuide? {
        if error == .javascriptFromAppleEventsOff {
            return SafariSetupGuide(
                title: "Allow JavaScript from Apple Events in Safari",
                steps: ["In Safari, open Settings > Advanced and tick Show features for web developers.",
                        "Choose Develop > Developer Settings and tick Allow JavaScript from Apple Events."],
                showsOpenSettings: false, fallback: fallbackText)
        }
        switch state {
        case .granted:
            return error == .automationDenied ? make(state: .denied, error: nil) : nil
        case .denied, .notDetermined:
            return SafariSetupGuide(
                title: state == .denied ? "Automation for Safari is off" : "Allow LF-AIWorkflow to control Safari",
                steps: ["Open System Settings > Privacy & Security > Automation.",
                        "Under LF-AIWorkflow, switch on Safari."],
                showsOpenSettings: true, fallback: fallbackText)
        case .safariNotRunning:
            return SafariSetupGuide(title: "Safari is not running", steps: ["Open Safari, then refresh the tab list."],
                                    showsOpenSettings: false, fallback: fallbackText)
        }
    }
}
