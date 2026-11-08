//
//  AppTheme.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// Immutable visual tokens. Views read tokens only and never branch on `id`, so a new style touches no view.
nonisolated struct AppTheme: Sendable, Equatable {
    let id: ArtStyle
    let lightPalette: ThemePalette
    let darkPalette: ThemePalette
    let stageColors: [PipelineStep: StageColorPair]

    let outlineWidth: CGFloat
    /// Rows, cards, fields.
    let cornerRadius: CGFloat
    /// Small fields, tags.
    let smallCornerRadius: CGFloat
    /// Peek bubble.
    let bubbleCornerRadius: CGFloat
    /// Bottom corners of the expanded panel shape.
    let panelCornerRadius: CGFloat
    /// In-panel approval sheet.
    let sheetCornerRadius: CGFloat
    /// Document and skill tags.
    let tagCornerRadius: CGFloat
    /// Review severity badges.
    let badgeCornerRadius: CGFloat
    /// Extra inset inside the panel so outlines and hard shadows are not clipped.
    let panelInset: CGFloat
    let shadow: ThemeShadow?

    /// Opacity of tinted fills: error strip, plan status pill, review severity badge.
    let subtleTintOpacity: Double
    let pillTintOpacity: Double
    let badgeTintOpacity: Double

    let headingFont: ThemeFont
    let titleFont: ThemeFont
    let subheadingFont: ThemeFont
    let bodyLargeFont: ThemeFont
    let bodyFont: ThemeFont
    let emphasisFont: ThemeFont
    let captionFont: ThemeFont
    let chipFont: ThemeFont
    let iconFont: ThemeFont
    let monoFont: ThemeFont
    let monoBodyFont: ThemeFont
    let peekFont: ThemeFont
    let countFont: ThemeFont

    let background: BackgroundStyle
    let peekStyle: PeekStyle
    let celebration: CelebrationStyle
    let statusFills: StatusFillStyle
    let mascotStyle: MascotStyle
    let mascot: MascotColors
    let progressBarStyle: ProgressBarStyle
    /// Fixed for every theme so the wings blend with the camera notch.
    let collapsedWingColor: ThemeColor
    /// Text on the wings; fixed like the wings themselves.
    let collapsedWingText: ThemeColor
    /// True when the accent token resolves to the macOS accent color (TD-059) instead of the palette's fixed accent.
    var followsSystemAccent = false

    /// Accent for tints and borders: the system accent when the theme follows it, else the palette token.
    /// Complexity: O(1) time, O(1) space
    func accentNSColor(for scheme: ColorScheme) -> NSColor {
        followsSystemAccent ? NSColor.controlAccentColor : palette(for: scheme).accent.nsColor
    }

    /// SwiftUI form of `accentNSColor(for:)`.
    /// Complexity: O(1) time, O(1) space
    func accentColor(for scheme: ColorScheme) -> Color { Color(nsColor: accentNSColor(for: scheme)) }

    /// Complexity: O(1) time, O(1) space
    func palette(for scheme: ColorScheme) -> ThemePalette {
        scheme == .dark ? darkPalette : lightPalette
    }

    /// Complexity: O(1) time, O(1) space
    func stageColor(_ step: PipelineStep, for scheme: ColorScheme) -> ThemeColor {
        stageColors[step]?.resolved(for: scheme) ?? palette(for: scheme).accent
    }

    /// Whether the halftone background is drawn; Reduce Transparency falls back to the plain panel color.
    /// Complexity: O(1) time, O(1) space
    func showsHalftone(reduceTransparency: Bool) -> Bool {
        guard case .halftone = background else { return false }
        return !reduceTransparency
    }

    /// Smallest `panelInset` that keeps the outline (half its width spills outward) and the hard shadow inside the fixed panel frame.
    /// Complexity: O(1) time, O(1) space
    var minimumPanelInset: CGFloat {
        let shadowReach = shadow.map { max($0.dx, $0.dy, 0) + $0.blur } ?? 0
        return outlineWidth > 0 || shadow != nil ? shadowReach + outlineWidth / 2 : 0
    }

    /// Fill of a surface role in one scheme.
    /// Complexity: O(1) time, O(1) space
    func fill(for role: SurfaceRole, scheme: ColorScheme) -> ThemeColor {
        let palette = palette(for: scheme)
        switch role {
        case .row, .tag: return palette.rowBackground
        case .attentionRow: return palette.attentionRowBackground
        case .field: return palette.fieldBackground
        case .sheet: return palette.sheetBackground
        case .terminal: return palette.terminalBackground
        }
    }

    /// Corner radius of a surface role.
    /// Complexity: O(1) time, O(1) space
    func cornerRadius(for role: SurfaceRole) -> CGFloat {
        switch role {
        case .row, .attentionRow: cornerRadius
        case .field, .terminal: smallCornerRadius
        case .sheet: sheetCornerRadius
        case .tag: tagCornerRadius
        }
    }

    /// Every (text, background) pair a view draws, for the contrast sweep. Solid status fills add their pairs.
    /// Complexity: O(s) time, O(s) space (s = pipeline steps)
    func allTextPairs(for scheme: ColorScheme) -> [(text: ThemeColor, background: ThemeColor, name: String)] {
        let palette = palette(for: scheme)
        let fixed = TextPairUsage.all.map {
            (text: $0.text.color(in: palette), background: $0.surface.color(in: self, scheme: scheme), name: $0.name)
        } + [
            (text: palette.terminalText, background: palette.terminalBackground.composited(over: palette.panelBackground), name: "terminal"),
        ]
        let stages = PipelineStep.allCases.map {
            (text: palette.onStageFill, background: stageColor($0, for: scheme), name: "on \($0.rawValue) fill")
        }
        let statusPairs: [(text: ThemeColor, background: ThemeColor, name: String)] = statusFills == .solid ? [
            (text: palette.onStageFill, background: palette.failedFill, name: "on failed fill"),
            (text: palette.onStageFill, background: palette.waitingFill, name: "on waiting fill"),
            (text: palette.onStageFill, background: palette.burstFill, name: "on burst fill"),
        ] : []
        return fixed + stages + statusPairs
    }
}
