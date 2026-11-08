//
//  TaskStatusLine.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The status text of a task, shared by the list row and the detail view. Solid themes show an attention status
/// as a flat waiting pill; tinted themes keep it as colored text.
struct TaskStatusLine: View {
    /// How the status text is drawn. Chosen by `style(needsAttention:fills:)`.
    enum Style: Equatable, Sendable {
        case pill, attentionText, plainText
    }

    let text: String
    let needsAttention: Bool
    let font: ThemeFont
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    /// Pure choice of drawing style, so the rule is testable without rendering.
    /// Complexity: O(1) time, O(1) space
    static func style(needsAttention: Bool, fills: StatusFillStyle) -> Style {
        guard needsAttention else { return .plainText }
        return fills == .solid ? .pill : .attentionText
    }

    var body: some View {
        switch Self.style(needsAttention: needsAttention, fills: theme.statusFills) {
        case .pill:
            Text(text)
                .font(font.font)
                .foregroundStyle(palette.onStageFill.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.waitingFill.color))
                .lineLimit(2)
        case .attentionText:
            Text(text)
                .font(font.font)
                .foregroundStyle(palette.warning.color)
                .lineLimit(2)
        case .plainText:
            Text(text)
                .font(font.font)
                .foregroundStyle(palette.secondaryText.color)
                .lineLimit(2)
        }
    }
}
