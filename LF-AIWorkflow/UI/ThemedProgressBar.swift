//
//  ThemedProgressBar.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Progress in the theme's style: the system linear bar, or a thick outlined striped bar for the comic theme.
struct ThemedProgressBar: View {
    let value: Double
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = theme.palette(for: scheme)
        switch theme.progressBarStyle {
        case .linear:
            ProgressView(value: value).progressViewStyle(.linear).tint(theme.accentColor(for: scheme))
        case .blocky:
            StripedProgressBar(fraction: value, fill: palette.accent, stripe: palette.onStageFill,
                               outline: palette.outline, outlineWidth: theme.outlineWidth)
        }
    }
}

/// A thick bar with diagonal stripes on the filled part and a black outline around the track.
struct StripedProgressBar: View {
    let fraction: Double
    let fill: ThemeColor
    let stripe: ThemeColor
    let outline: ThemeColor
    let outlineWidth: CGFloat

    static let height: CGFloat = 12
    static let stripeSpacing: CGFloat = 8
    static let stripeWidth: CGFloat = 3
    static let stripeAlpha: Double = 0.35

    /// Complexity: O(w / stripe spacing) time, O(1) space
    var body: some View {
        Canvas { context, size in
            let clamped = min(max(fraction, 0), 1)
            let track = CGRect(origin: .zero, size: size)
            let filled = CGRect(x: 0, y: 0, width: size.width * clamped, height: size.height)
            context.fill(Path(filled), with: .color(fill.color))
            var stripes = context
            stripes.clip(to: Path(filled))
            var x: CGFloat = -size.height
            while x < filled.maxX {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                stripes.stroke(line, with: .color(stripe.fading(Self.stripeAlpha).color), lineWidth: Self.stripeWidth)
                x += Self.stripeSpacing
            }
            context.stroke(Path(track), with: .color(outline.color), lineWidth: outlineWidth)
        }
        .frame(height: Self.height)
    }
}
