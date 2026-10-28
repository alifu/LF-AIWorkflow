//
//  CollapsedView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Collapsed state. On a notched Mac nothing is drawn (the hit area is exactly the notch); without a notch a
/// half-circle tab with the mascot and the active count hangs from the menu bar.
struct CollapsedView: View {
    let kind: NotchKind
    let summary: CollapsedSummary
    let onActivate: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.accessibilityLabel)
            .accessibilityHint("Opens the task panel")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onActivate)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .notch:
            ThemeColor.clear.color
        case .none:
            ZStack {
                HalfCircleShape().fill(theme.collapsedWingColor.color)
                HStack(spacing: 6) {
                    MascotView(pose: MascotPose.pose(for: summary), size: 18)
                    if summary.activeCount > 0 {
                        Text("● \(summary.activeCount)")
                            .font(theme.countFont.font)
                            .foregroundStyle(theme.collapsedWingText.color)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }
}

#Preview("No notch, 2 running") {
    CollapsedView(kind: .none, summary: CollapsedSummary(activeCount: 2, leadStep: .code, attentionCount: 0), onActivate: {})
        .frame(width: NotchGeometry.halfCircleWidth, height: 24)
        .padding()
}

#Preview("Notch (invisible)") {
    CollapsedView(kind: .notch(width: 200, height: 32), summary: CollapsedSummary(activeCount: 0, leadStep: nil, attentionCount: 0), onActivate: {})
        .frame(width: 200, height: 32)
        .border(.red)
        .padding()
}
