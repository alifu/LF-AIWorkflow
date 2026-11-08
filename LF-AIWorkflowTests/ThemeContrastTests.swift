//
//  ThemeContrastTests.swift
//  LF-AIWorkflowTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_AIWorkflow

/// Step 11 sweep: every (text, background) pair a view draws, in both themes and both color schemes, reaches WCAG AA.
struct ThemeContrastTests {
    private let minimumContrast = 4.5
    private let themes: [AppTheme] = [.classic, .popArt]

    @Test(arguments: [ColorScheme.light, .dark])
    func everyPairInEveryThemeReachesAA(scheme: ColorScheme) {
        for theme in themes {
            for pair in theme.allTextPairs(for: scheme) {
                let ratio = pair.text.contrast(against: pair.background)
                #expect(ratio >= minimumContrast, "\(theme.id) \(scheme) \(pair.name) = \(ratio), needs \(minimumContrast)")
            }
        }
    }

    private func pair(_ theme: AppTheme, _ scheme: ColorScheme, _ name: String) -> (text: ThemeColor, background: ThemeColor)? {
        theme.allTextPairs(for: scheme).first { $0.name == name }.map { ($0.text, $0.background) }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func popArtSweepCoversFailedWaitingAndBurstFillsWithTheRightColors(scheme: ColorScheme) throws {
        let palette = AppTheme.popArt.palette(for: scheme)
        let failed = try #require(pair(.popArt, scheme, "on failed fill"))
        let waiting = try #require(pair(.popArt, scheme, "on waiting fill"))
        let burst = try #require(pair(.popArt, scheme, "on burst fill"))
        #expect(failed.text == palette.onStageFill && failed.background == palette.failedFill)
        #expect(waiting.text == palette.onStageFill && waiting.background == palette.waitingFill)
        #expect(burst.text == palette.onStageFill && burst.background == palette.burstFill)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func classicSweepKeepsItsChecksAndSkipsPopArtFills(scheme: ColorScheme) throws {
        let palette = AppTheme.classic.palette(for: scheme)
        let primary = try #require(pair(.classic, scheme, "primaryText on panel"))
        #expect(primary.text == palette.primaryText && primary.background == palette.panelBackground)
        let plan = try #require(pair(.classic, scheme, "on plan fill"))
        #expect(plan.text == palette.onStageFill && plan.background == AppTheme.classic.stageColor(.plan, for: scheme))
        #expect(pair(.classic, scheme, "on burst fill") == nil)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func sweepCoversTheTextTheViewsDrawOnTheirRealBackgrounds(scheme: ColorScheme) throws {
        for theme in themes {
            let palette = theme.palette(for: scheme)
            let panel = palette.panelBackground
            let dismiss = try #require(pair(theme, scheme, "dismissText on panel"))
            #expect(dismiss.text == palette.dismissText && dismiss.background == panel)
            let composer = try #require(pair(theme, scheme, "warning on warningSubtleTint"))
            #expect(composer.text == palette.warning)
            #expect(composer.background == palette.warning.fading(theme.subtleTintOpacity).composited(over: panel))
            let accent = try #require(pair(theme, scheme, "accent on panel"))
            #expect(accent.text == palette.accent && accent.background == panel)
            let secondaryRow = try #require(pair(theme, scheme, "secondaryText on attentionRow"))
            #expect(secondaryRow.text == palette.secondaryText)
            #expect(secondaryRow.background == palette.attentionRowBackground.composited(over: panel))
            let sheetField = try #require(pair(theme, scheme, "primaryText on fieldOnSheet"))
            #expect(sheetField.background == palette.fieldBackground.composited(over: palette.sheetBackground.composited(over: panel)))
        }
    }

    @Test func everyPaletteTokenTheViewsUseAsTextIsInTheSweep() throws {
        let used = try ThemeUsageGuard.paletteTextTokens()
        let swept = Set(TextPairUsage.all.map(\.text.rawValue)).union(["onStageFill", "terminalText"])
        #expect(used.subtracting(swept).isEmpty, "Views draw text in tokens the contrast sweep skips: \(used.subtracting(swept).sorted())")
        #expect(used.contains("secondaryText") && used.contains("dismissText"), "the scan found no tokens; is the source copy broken?")
    }

    @Test func pairNamesAreUniquePerTheme() {
        for theme in themes {
            let names = theme.allTextPairs(for: .dark).map(\.name)
            #expect(Set(names).count == names.count, "\(theme.id)")
        }
    }
}

@MainActor
@Suite struct ClassicAccentTests {
    @Test func classicAccentResolvesToTheSystemAccent() {
        for scheme in [ColorScheme.light, .dark] {
            #expect(AppTheme.classic.accentNSColor(for: scheme) == NSColor.controlAccentColor)
        }
    }

    @Test func popArtAccentStaysItsFixedToken() {
        for scheme in [ColorScheme.light, .dark] {
            #expect(AppTheme.popArt.accentNSColor(for: scheme) == AppTheme.popArt.palette(for: scheme).accent.nsColor)
        }
    }
}
