//
//  PeekBubble.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Short alert below the menu bar. Hover or click opens the panel on the task.
/// Line style keeps the mascot inside a plain rounded panel; bubble style puts the mascot beside a comic bubble whose tail points at it.
struct PeekBubble: View {
    let message: PeekMessage
    let pose: MascotPose
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    private static let contentInset: CGFloat = 14
    private static let mascotSize: CGFloat = 28

    var body: some View {
        let palette = theme.palette(for: scheme)
        let isBubble = theme.peekStyle == .bubble
        HStack(spacing: 6) {
            if isBubble { mascot }
            HStack(spacing: 10) {
                if !isBubble { mascot }
                Text(message.text)
                    .font(theme.peekFont.font)
                    .foregroundStyle(palette.emphasizedText.color)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(theme.captionFont.weighted(.bold).font)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.dismissText.color)
                .accessibilityLabel("Dismiss alert")
            }
            .padding(.leading, Self.contentInset + (isBubble ? ComicBubble.defaultTailLength : 0))
            .padding(.trailing, Self.contentInset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { bubbleBackground(palette) }
            .contentShape(bubbleShape)
        }
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
        .accessibilityHint("Opens the task")
        .accessibilityAddTraits(.isButton)
        .onAppear { AccessibilityNotification.Announcement(message.text).post() }
    }

    private var mascot: some View {
        MascotView(pose: pose, size: Self.mascotSize)
    }

    /// Complexity: O(1) time, O(1) space
    private var bubbleShape: AnyShape {
        switch theme.peekStyle {
        case .line: AnyShape(RoundedRectangle(cornerRadius: theme.bubbleCornerRadius, style: .continuous))
        case .bubble: AnyShape(ComicBubble(cornerRadius: theme.bubbleCornerRadius, tailLength: ComicBubble.defaultTailLength))
        }
    }

    /// Complexity: O(1) time, O(1) space
    @ViewBuilder private func bubbleBackground(_ palette: ThemePalette) -> some View {
        let shape = bubbleShape
        shape.fill(palette.panelBackground.color)
            .overlay {
                if theme.peekStyle == .bubble {
                    shape.stroke(palette.outline.color, lineWidth: theme.outlineWidth)
                }
            }
    }
}

#Preview("Line") {
    PeekBubble(message: PeekMessage(taskID: UUID(), text: "Add dark mode: plan ready, approve?", kind: .planReady, sequence: 1),
               pose: .attention, onOpen: {}, onDismiss: {})
        .frame(width: 320, height: 80)
        .padding()
        .environment(\.appTheme, .classic)
}

#Preview("Comic bubble") {
    PeekBubble(message: PeekMessage(taskID: UUID(), text: "Add dark mode: plan ready, approve?", kind: .planReady, sequence: 1),
               pose: .attention, onOpen: {}, onDismiss: {})
        .frame(width: 320, height: 80)
        .padding()
        .environment(\.appTheme, .popArt)
}
