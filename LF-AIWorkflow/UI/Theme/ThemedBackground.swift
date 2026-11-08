//
//  ThemedBackground.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The panel's paper: the theme's panel color, with the halftone dot tile on top when the theme has one
/// and Reduce Transparency is off.
struct ThemedBackground: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = theme.palette(for: scheme)
        ZStack {
            palette.panelBackground.color
            if case .halftone(let spacing, let radius) = theme.background,
               theme.showsHalftone(reduceTransparency: reduceTransparency) {
                HalftoneTile(spacing: spacing, radius: radius, dot: palette.halftoneDot)
            }
        }
    }
}

/// Repeats one cached tile. The tile does not depend on the panel size, so resizing never renders again.
struct HalftoneTile: View {
    let spacing: CGFloat
    let radius: CGFloat
    let dot: ThemeColor
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let key = HalftoneKey.tile(spacing: spacing, radius: radius, dot: dot, scale: displayScale)
        if let image = HalftoneImageCache.shared.image(for: key) {
            Image(decorative: image, scale: displayScale).resizable(resizingMode: .tile)
        }
    }
}
