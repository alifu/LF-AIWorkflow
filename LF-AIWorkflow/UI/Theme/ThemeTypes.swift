//
//  ThemeTypes.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// An sRGB color with alpha, kept as plain numbers so themes stay `Equatable` and contrast can be computed in tests.
nonisolated struct ThemeColor: Sendable, Equatable, Hashable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    static func white(_ level: Double, alpha: Double = 1) -> ThemeColor { ThemeColor(level, level, level, alpha) }

    /// Fully transparent; used for window backdrops.
    static let clear = ThemeColor(0, 0, 0, 0)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// The same color at a different alpha (used for tinted fills, so views never write an opacity literal).
    /// Complexity: O(1) time, O(1) space
    func fading(_ alpha: Double) -> ThemeColor { ThemeColor(r, g, b, alpha) }

    /// This color painted over `background` (source-over); the result is opaque when `background` is.
    /// Complexity: O(1) time, O(1) space
    func composited(over background: ThemeColor) -> ThemeColor {
        let outAlpha = a + background.a * (1 - a)
        guard outAlpha > 0 else { return ThemeColor(0, 0, 0, 0) }
        func mix(_ top: Double, _ bottom: Double) -> Double {
            (top * a + bottom * background.a * (1 - a)) / outAlpha
        }
        return ThemeColor(mix(r, background.r), mix(g, background.g), mix(b, background.b), outAlpha)
    }

    /// WCAG relative luminance of the color as if opaque.
    /// Complexity: O(1) time, O(1) space
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio (1...21) of this color drawn over `background`. Translucent text is composited first.
    /// Complexity: O(1) time, O(1) space
    func contrast(against background: ThemeColor) -> Double {
        let opaqueBackground = ThemeColor(background.r, background.g, background.b)
        let foreground = composited(over: opaqueBackground)
        let (lighter, darker) = (max(foreground.relativeLuminance, opaqueBackground.relativeLuminance),
                                 min(foreground.relativeLuminance, opaqueBackground.relativeLuminance))
        return (lighter + 0.05) / (darker + 0.05)
    }
}

nonisolated struct ThemeFont: Sendable, Equatable {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let uppercase: Bool
    let width: Font.Width?

    init(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
         uppercase: Bool = false, width: Font.Width? = nil) {
        self.size = size; self.weight = weight; self.design = design
        self.uppercase = uppercase; self.width = width
    }

    var font: Font {
        let base = Font.system(size: size, weight: weight, design: design)
        return width.map { base.width($0) } ?? base
    }

    /// The same face at another weight.
    /// Complexity: O(1) time, O(1) space
    func weighted(_ newWeight: Font.Weight) -> ThemeFont {
        ThemeFont(size: size, weight: newWeight, design: design, uppercase: uppercase, width: width)
    }

    /// Apply with `.textCase(_:)`; nil leaves the text as typed.
    var textCase: Text.Case? { uppercase ? .uppercase : nil }
}

nonisolated struct ThemeShadow: Sendable, Equatable {
    let dx: CGFloat
    let dy: CGFloat
    let blur: CGFloat
    let color: ThemeColor
}

nonisolated enum PeekStyle: Sendable, Equatable { case line, bubble }
nonisolated enum CelebrationStyle: Sendable, Equatable { case fade, burst }
/// How failed and waiting chips are filled: `tint` keeps a faint wash with colored text, `solid` uses a flat fill with black text.
nonisolated enum StatusFillStyle: Sendable, Equatable { case tint, solid }
nonisolated enum MascotStyle: Sendable, Equatable { case soft, outlined }
nonisolated enum ProgressBarStyle: Sendable, Equatable { case linear, blocky }
nonisolated enum BackgroundStyle: Sendable, Equatable {
    case plain
    case halftone(dotSpacing: CGFloat, dotRadius: CGFloat)
}

/// The mascot's fixed illustration colors. The mascot is drawn on the black wings too, so these do not vary by scheme.
nonisolated struct MascotColors: Sendable, Equatable {
    let face: ThemeColor
    let features: ThemeColor
    let sweat: ThemeColor
    let alert: ThemeColor
}

/// Every color a view may need in one color scheme.
nonisolated struct ThemePalette: Sendable, Equatable {
    let panelBackground: ThemeColor
    let rowBackground: ThemeColor
    let attentionRowBackground: ThemeColor
    let chipBackground: ThemeColor
    let chipDoneBackground: ThemeColor
    let fieldBackground: ThemeColor
    let sheetBackground: ThemeColor
    let primaryText: ThemeColor
    let secondaryText: ThemeColor
    /// Text that must be brightest on the panel (peek alerts).
    let emphasizedText: ThemeColor
    let dismissText: ThemeColor
    let accent: ThemeColor
    let divider: ThemeColor
    /// Hairline around sheets and outlines of outlined themes.
    let outline: ThemeColor
    /// Dashed border shown while a drop is possible.
    let dropBorder: ThemeColor
    /// Dimming behind an in-panel sheet.
    let scrim: ThemeColor
    let terminalBackground: ThemeColor
    let terminalText: ThemeColor
    let onStageFill: ThemeColor
    /// Flat fills for the failed and waiting states (chips carry an icon and text marker too) and for celebration bursts.
    let failedFill: ThemeColor
    let waitingFill: ThemeColor
    let burstFill: ThemeColor
    /// Dot color of a halftone background; clear when the theme has none.
    let halftoneDot: ThemeColor
    /// Semantic colors. Each is legible as text on `panelBackground` in its scheme.
    let failure: ThemeColor
    let warning: ThemeColor
    let caution: ThemeColor
    let success: ThemeColor
    let neutral: ThemeColor
}

/// One stage color per color scheme.
nonisolated struct StageColorPair: Sendable, Equatable {
    let light: ThemeColor
    let dark: ThemeColor

    func resolved(for scheme: ColorScheme) -> ThemeColor { scheme == .dark ? dark : light }
}

/// How a `ThemedSurface` is drawn: its fill and corner come from the theme, so a view names a role, not a style.
nonisolated enum SurfaceRole: Sendable, Equatable, CaseIterable {
    case row, attentionRow, field, sheet, tag, terminal
}
