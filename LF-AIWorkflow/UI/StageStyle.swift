//
//  StageStyle.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The only place that maps a pipeline step to color, icon and label (Phase 6 T6.5 swaps this for theme tokens).
/// State is never conveyed by color alone: every chip also carries an icon, a label and a text marker.
enum StageStyle {
    static func color(_ step: PipelineStep) -> Color {
        switch step {
        case .plan: .blue
        case .code: .indigo
        case .test: .teal
        case .fix: .orange
        case .review: .purple
        }
    }

    static func icon(_ step: PipelineStep) -> String {
        switch step {
        case .plan: "list.bullet.clipboard"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .test: "checkmark.seal"
        case .fix: "wrench.and.screwdriver"
        case .review: "eye"
        }
    }

    static func label(_ step: PipelineStep) -> String {
        switch step {
        case .plan: "Plan"
        case .code: "Code"
        case .test: "Test"
        case .fix: "Fix"
        case .review: "Review"
        }
    }

    /// Text marker for a chip status.
    static func marker(_ status: StageChip.Status) -> String {
        switch status {
        case .pending: "○"
        case .active: "●"
        case .done: "✓"
        case .failed: "✕"
        }
    }
}
