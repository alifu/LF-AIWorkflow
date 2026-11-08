//
//  CelebrationPolicy.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Pure rules for the done/failed celebration and Reduce Motion. Views read these, so the rules are testable without pixels.
nonisolated enum CelebrationPolicy {
    /// How long the burst stays on screen.
    static let duration: Duration = .milliseconds(1200)

    /// The burst word for a status; only done and failed celebrate.
    /// Complexity: O(1) time, O(1) space
    static func label(for status: StageChip.Status) -> String? {
        switch status {
        case .done: "DONE!"
        case .failed: "OOPS!"
        case .pending, .active: nil
        }
    }

    /// Reduce Motion: nil, so the burst appears without animation.
    /// Complexity: O(1) time, O(1) space
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)
    }

    /// Reduce Motion stops bouncing.
    /// Complexity: O(1) time, O(1) space
    static func bouncesMascot(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
