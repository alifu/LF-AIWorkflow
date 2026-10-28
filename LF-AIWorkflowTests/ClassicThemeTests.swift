//
//  ClassicThemeTests.swift
//  LF-AIWorkflowTests
//

import SwiftUI
import Testing
@testable import LF_AIWorkflow

/// Classic reproduces the look shipped in Phase 5 (the user's decision); these values are transcribed from the views.
struct ClassicThemeTests {
    private let theme = AppTheme.classic

    @Test func identifiesAsClassic() {
        #expect(theme.id == .classic)
    }

    @Test func stageColorsKeepTheShippedPalette() {
        // plan blue, code indigo, test teal, fix orange, review purple (system colors, per scheme)
        #expect(theme.stageColor(.plan, for: .dark) == ThemeColor(0.039, 0.518, 1.0))
        #expect(theme.stageColor(.code, for: .dark) == ThemeColor(0.42, 0.41, 0.95))
        #expect(theme.stageColor(.test, for: .dark) == ThemeColor(0.251, 0.784, 0.878))
        #expect(theme.stageColor(.fix, for: .dark) == ThemeColor(1.0, 0.624, 0.039))
        #expect(theme.stageColor(.review, for: .dark) == ThemeColor(0.749, 0.353, 0.949))
        #expect(theme.stageColor(.fix, for: .light) == ThemeColor(0.65, 0.38, 0.0))
    }

    @Test func everyStepHasADistinctColorInBothSchemes() {
        for scheme in [ColorScheme.light, .dark] {
            let colors = PipelineStep.allCases.map { theme.stageColor($0, for: scheme) }
            #expect(Set(colors.map { "\($0.r)-\($0.g)-\($0.b)" }).count == PipelineStep.allCases.count)
        }
    }

    @Test func fontsMatchTheShippedLiterals() {
        #expect(theme.headingFont == ThemeFont(size: 13, weight: .semibold))
        #expect(theme.bodyFont == ThemeFont(size: 11))
        #expect(theme.chipFont == ThemeFont(size: 10))
        #expect(theme.captionFont == ThemeFont(size: 10))
        #expect(theme.monoFont == ThemeFont(size: 10, design: .monospaced))
    }

    @Test func geometryMatchesTheShippedLiterals() {
        #expect(theme.cornerRadius == 10)
        #expect(theme.smallCornerRadius == 8)
        #expect(theme.bubbleCornerRadius == 18)
        #expect(theme.panelCornerRadius == 24)
        #expect(theme.outlineWidth == 0)
        #expect(theme.panelInset == 0)
        #expect(theme.shadow == nil)
    }

    @Test func styleTokensAreTheQuietOnes() {
        #expect(theme.background == .plain)
        #expect(theme.peekStyle == .line)
        #expect(theme.celebration == .fade)
        #expect(theme.mascotStyle == .soft)
        #expect(theme.progressBarStyle == .linear)
    }

    @Test func darkPaletteIsTheShippedBlackPanel() {
        let dark = theme.palette(for: .dark)
        #expect(dark.panelBackground == .white(0))
        #expect(dark.rowBackground == .white(1, alpha: 0.07))
        #expect(dark.chipBackground == .white(1, alpha: 0.06))
        #expect(dark.divider == .white(1, alpha: 0.1))
        #expect(dark.onStageFill == .white(0))
    }

    @Test func collapsedWingsAreBlack() {
        #expect(theme.collapsedWingColor == .white(0))
    }

    @Test func lightAndDarkPalettesDiffer() {
        #expect(theme.palette(for: .light) != theme.palette(for: .dark))
    }

    @Test func textReadsOnThePanelInBothSchemes() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = theme.palette(for: scheme)
            #expect(palette.primaryText.contrast(against: palette.panelBackground) >= 4.5)
            #expect(palette.secondaryText.contrast(against: palette.panelBackground) >= 4.5)
        }
    }

    @Test func shippedFontRolesKeepTheirSizes() {
        #expect(theme.titleFont == ThemeFont(size: 14, weight: .semibold))
        #expect(theme.subheadingFont == ThemeFont(size: 12, weight: .semibold))
        #expect(theme.bodyLargeFont == ThemeFont(size: 12))
        #expect(theme.emphasisFont == ThemeFont(size: 11, weight: .semibold))
        #expect(theme.iconFont == ThemeFont(size: 9))
        #expect(theme.monoBodyFont == ThemeFont(size: 11, design: .monospaced))
        #expect(theme.peekFont == ThemeFont(size: 13, weight: .medium))
        #expect(theme.countFont == ThemeFont(size: 11, weight: .semibold, design: .rounded))
    }

    @Test func shippedRadiiAndTintStrengthsKeepTheirValues() {
        #expect(theme.sheetCornerRadius == 14)
        #expect(theme.tagCornerRadius == 6)
        #expect(theme.badgeCornerRadius == 4)
        #expect(theme.subtleTintOpacity == 0.12)
        #expect(theme.pillTintOpacity == 0.25)
        #expect(theme.badgeTintOpacity == 0.28)
    }

    @Test func darkSemanticColorsAreTheSystemColors() {
        let dark = theme.palette(for: .dark)
        #expect(dark.failure == ThemeColor(1.0, 0.271, 0.227))
        #expect(dark.warning == ThemeColor(1.0, 0.624, 0.039))
        #expect(dark.caution == ThemeColor(1.0, 0.839, 0.039))
        #expect(dark.success == ThemeColor(0.196, 0.843, 0.294))
        #expect(dark.neutral == ThemeColor(0.557, 0.557, 0.576))
    }

    @Test func darkSurfacesKeepTheShippedAlphas() {
        let dark = theme.palette(for: .dark)
        #expect(dark.attentionRowBackground == .white(1, alpha: 0.12))
        #expect(dark.chipDoneBackground == .white(1, alpha: 0.14))
        #expect(dark.fieldBackground == .white(1, alpha: 0.08))
        #expect(dark.sheetBackground == .white(0.14))
        #expect(dark.dismissText == .white(1, alpha: 0.7))
        #expect(dark.dropBorder == .white(1, alpha: 0.2))
        #expect(dark.outline == .white(1, alpha: 0.15))
        #expect(dark.scrim == .white(0, alpha: 0.55))
        #expect(dark.emphasizedText == .white(1))
    }

    @Test func wingsAndMascotAreFixedAcrossSchemes() {
        #expect(theme.collapsedWingColor == .white(0))
        #expect(theme.collapsedWingText == .white(1))
        #expect(theme.mascot.face == .white(1))
        #expect(theme.mascot.features == .white(0.1))
        #expect(theme.mascot.sweat == ThemeColor(0.392, 0.824, 1.0))
        #expect(theme.mascot.alert == ThemeColor(1.0, 0.839, 0.039))
    }

    @Test func surfaceRolesMapToTheirPaletteFillsAndRadii() {
        let dark = ColorScheme.dark
        #expect(theme.fill(for: .row, scheme: dark) == theme.darkPalette.rowBackground)
        #expect(theme.fill(for: .tag, scheme: dark) == theme.darkPalette.rowBackground)
        #expect(theme.fill(for: .attentionRow, scheme: dark) == theme.darkPalette.attentionRowBackground)
        #expect(theme.fill(for: .terminal, scheme: dark) == theme.darkPalette.terminalBackground)
        #expect(theme.cornerRadius(for: .row) == 10)
        #expect(theme.cornerRadius(for: .field) == 8)
        #expect(theme.cornerRadius(for: .terminal) == 8)
        #expect(theme.cornerRadius(for: .sheet) == 14)
        #expect(theme.cornerRadius(for: .tag) == 6)
    }

    @Test func semanticTextIsLegibleOnThePanelInBothSchemes() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = theme.palette(for: scheme)
            for text in [palette.failure, palette.warning, palette.caution, palette.success, palette.emphasizedText] {
                #expect(text.contrast(against: palette.panelBackground) >= 4.5)
            }
        }
    }
}

