//
//  ArtStylePreview.swift
//  LF-AIWorkflow
//
//  Lives in UI/Theme/ on purpose: it names the art styles, which views outside the theme folder may not do.

import SwiftUI

extension ArtStyle {
    /// Picker label.
    /// Complexity: O(1) time, O(1) space
    var title: String {
        switch self {
        case .classic: "Classic"
        case .popArt: "Pop Art"
        }
    }
}

/// Pure selection of the themes the General tab previews side by side, each injected with its own environment.
@MainActor
enum ArtStylePreviewCandidates {
    /// Complexity: O(1) time, O(1) space
    static func theme(for style: ArtStyle) -> AppTheme {
        switch style {
        case .classic: .classic
        case .popArt: .popArt
        }
    }

    /// Complexity: O(s) time, O(s) space (s = art styles)
    static func candidates() -> [(style: ArtStyle, theme: AppTheme)] {
        ArtStyle.allCases.map { ($0, theme(for: $0)) }
    }
}

/// Live sample of every candidate look: a stage chip, a task row, a peek message and the four mascot poses.
/// Each sample gets its own `appTheme` environment, so the preview never depends on the stored choice.
struct ArtStylePreview: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(ArtStylePreviewCandidates.candidates(), id: \.style) { candidate in
                ArtStyleSample(theme: candidate.theme)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One candidate's sample card: injects its own theme into the card's content, so the card reads tokens from it.
private struct ArtStyleSample: View {
    let theme: AppTheme

    var body: some View {
        ArtStyleSampleCard()
            .environment(\.appTheme, theme)
    }
}

/// Reads tokens from the environment (the candidate's theme) and draws the sample.
private struct ArtStyleSampleCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private static let chips = [
        StageChip(step: .plan, status: .done, detail: nil),
        StageChip(step: .code, status: .active, detail: nil),
    ]
    private static let peek = PeekMessage(taskID: UUID(), text: "Plan ready, approve?", kind: .planReady, sequence: 1)

    var body: some View {
        let palette = theme.palette(for: scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.id.title)
                .font(theme.captionFont.font)
                .foregroundStyle(palette.secondaryText.color)
            StageChipStrip(chips: Self.chips)
            HStack(spacing: 6) {
                MascotView(pose: .idle, size: 32)
                MascotView(pose: .typing, size: 32)
                MascotView(pose: .done, size: 32)
                MascotView(pose: .error, size: 32)
            }
            PeekBubble(message: Self.peek, pose: .attention, onOpen: {}, onDismiss: {})
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedSurface(.row)
    }
}
