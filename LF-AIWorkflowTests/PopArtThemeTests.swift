//
//  PopArtThemeTests.swift
//  LF-AIWorkflowTests
//

import SwiftUI
import Testing
@testable import LF_AIWorkflow

struct PopArtThemeTests {
    private let theme = AppTheme.popArt
    private let schemes: [ColorScheme] = [.light, .dark]
    private let minimumContrast = 4.5

    // MARK: Tokens

    @Test func identifiesAsPopArt() { #expect(theme.id == .popArt) }

    @Test func stageColorsFollowThePlanTable() {
        for scheme in schemes {
            let plan: ThemeColor = theme.stageColor(.plan, for: scheme)
            #expect(plan.r > 0.9, "plan magenta red")
            #expect(plan.g < 0.3, "plan magenta green")
            #expect(plan.b > 0.4, "plan magenta blue")
            let code: ThemeColor = theme.stageColor(.code, for: scheme)
            #expect(code.r < 0.2, "code cyan red")
            #expect(code.g > 0.7, "code cyan green")
            #expect(code.b > 0.9, "code cyan blue")
            let test: ThemeColor = theme.stageColor(.test, for: scheme)
            let redGreenGap: Double = abs(test.r - test.g)
            let greenBlueGap: Double = abs(test.g - test.b)
            #expect(redGreenGap < 0.05, "test gray")
            #expect(greenBlueGap < 0.05, "test gray")
            let fix: ThemeColor = theme.stageColor(.fix, for: scheme)
            #expect(fix.r > 0.9, "fix yellow red")
            #expect(fix.g > 0.8, "fix yellow green")
            #expect(fix.b < 0.2, "fix yellow blue")
            let review: ThemeColor = theme.stageColor(.review, for: scheme)
            #expect(review.g > review.r, "review green")
            #expect(review.g > review.b, "review green")
        }
    }

    @Test func stageColorsAreDistinct() {
        for scheme in schemes {
            let keys = PipelineStep.allCases.map { step -> String in
                let c = theme.stageColor(step, for: scheme)
                return "\(c.r)-\(c.g)-\(c.b)"
            }
            #expect(Set(keys).count == PipelineStep.allCases.count)
        }
    }

    @Test func textOnColorIsAlwaysBlack() {
        for scheme in schemes { #expect(theme.palette(for: scheme).onStageFill == .white(0)) }
    }

    @Test func geometryAndChrome() {
        #expect(theme.outlineWidth == 2.5)
        #expect(theme.cornerRadius == 6)
        #expect(theme.smallCornerRadius == 6)
        #expect(theme.shadow == ThemeShadow(dx: 4, dy: 4, blur: 0, color: .white(0)))
        for scheme in schemes { #expect(theme.palette(for: scheme).outline == .white(0)) }
    }

    @Test func paperIsCreamInLightAndNavyInDark() {
        let light = theme.lightPalette.panelBackground
        #expect(light.r > 0.9, "cream is light")
        #expect(light.g > 0.85, "cream is light")
        #expect(light.b < light.r, "cream is warm")
        let dark = theme.darkPalette.panelBackground
        #expect(dark.b > dark.r, "navy is blue")
        #expect(dark.b > dark.g, "navy is blue")
        #expect(dark.relativeLuminance < 0.05, "navy is deep")
    }

    @Test func headingsAndChipsAreHeavyCondensedUppercase() {
        for font in [theme.headingFont, theme.titleFont, theme.subheadingFont, theme.chipFont] {
            #expect(font.uppercase)
            #expect(font.width == .condensed)
            #expect([Font.Weight.heavy, .black].contains(font.weight))
        }
        #expect(theme.headingFont.weight == .black)
    }

    @Test func bodyTextIsNeverUppercasedAndLogsStayMonospaced() {
        for font in [theme.bodyFont, theme.bodyLargeFont, theme.captionFont, theme.emphasisFont,
                     theme.monoFont, theme.monoBodyFont, theme.peekFont, theme.iconFont, theme.countFont] {
            #expect(!font.uppercase)
        }
        #expect(theme.monoFont.design == .monospaced)
        #expect(theme.monoBodyFont.design == .monospaced)
    }

    @Test func styleTokens() {
        #expect(theme.peekStyle == .bubble)
        #expect(theme.celebration == .burst)
        #expect(theme.mascotStyle == .outlined)
        #expect(theme.progressBarStyle == .blocky)
        guard case .halftone(let spacing, let radius) = theme.background else {
            Issue.record("background must be halftone"); return
        }
        #expect(spacing > radius * 2)
        #expect(radius > 0)
    }

    @Test func collapsedWingsStayBlack() {
        #expect(theme.collapsedWingColor == .white(0))
        #expect(theme.collapsedWingText == .white(1))
    }

    @Test func halftoneFollowsReduceTransparency() {
        #expect(theme.showsHalftone(reduceTransparency: false))
        #expect(!theme.showsHalftone(reduceTransparency: true))
        #expect(!AppTheme.classic.showsHalftone(reduceTransparency: false))
    }

    // MARK: Chrome is not clipped

    @Test func panelInsetCoversOutlineAndHardShadow() {
        #expect(theme.panelInset == 6)
        #expect(theme.panelInset >= theme.minimumPanelInset)
        let expectedInset: CGFloat = 5.25
        #expect(theme.minimumPanelInset == expectedInset)
        #expect(AppTheme.classic.minimumPanelInset == 0)
        #expect(AppTheme.classic.panelInset >= AppTheme.classic.minimumPanelInset)
    }

    // MARK: Contrast (every pair a view draws)

    private func panelTint(_ color: ThemeColor, _ alpha: Double, _ palette: ThemePalette) -> ThemeColor {
        color.fading(alpha).composited(over: palette.panelBackground)
    }

    private func pairs(_ scheme: ColorScheme) -> [(String, ThemeColor, ThemeColor)] {
        let p = theme.palette(for: scheme)
        let panel = p.panelBackground
        let row = p.rowBackground.composited(over: panel)
        let attention = p.attentionRowBackground.composited(over: panel)
        let chip = p.chipBackground.composited(over: panel)
        let chipDone = p.chipDoneBackground.composited(over: panel)
        let field = p.fieldBackground.composited(over: panel)
        let dotted = p.halftoneDot.composited(over: panel)
        var list: [(String, ThemeColor, ThemeColor)] = [
            ("primary/panel", p.primaryText, panel), ("primary/row", p.primaryText, row),
            ("primary/attention", p.primaryText, attention), ("primary/field", p.primaryText, field),
            ("primary/chipDone", p.primaryText, chipDone), ("primary/sheet", p.primaryText, p.sheetBackground),
            ("secondary/panel", p.secondaryText, panel), ("secondary/row", p.secondaryText, row),
            ("secondary/attention", p.secondaryText, attention), ("secondary/chip", p.secondaryText, chip),
            ("secondary/field", p.secondaryText, field), ("secondary/sheet", p.secondaryText, p.sheetBackground),
            ("secondary/halftone dot", p.secondaryText, dotted), ("primary/halftone dot", p.primaryText, dotted),
            ("emphasized/panel (bubble)", p.emphasizedText, panel), ("dismiss/panel (bubble)", p.dismissText, panel),
            ("terminal", p.terminalText, p.terminalBackground.composited(over: panel)),
            ("accent/panel", p.accent, panel),
        ]
        for (name, color) in [("failure", p.failure), ("warning", p.warning), ("caution", p.caution),
                              ("success", p.success), ("neutral", p.neutral)] {
            list.append(("\(name)/panel", color, panel))
            list.append(("\(name)/row", color, row))
            list.append(("\(name)/sheet", color, p.sheetBackground))
        }
        list.append(("failure/chip", p.failure, chip))
        list.append(("warning/attention", p.warning, attention))
        list.append(("warning/subtle tint", p.warning, panelTint(p.warning, theme.subtleTintOpacity, p)))
        list.append(("failure/subtle tint", p.failure, panelTint(p.failure, theme.subtleTintOpacity, p)))
        for tint in [p.success, p.warning] {
            list.append(("primary/plan pill", p.primaryText, panelTint(tint, theme.pillTintOpacity, p)))
        }
        for tint in [p.failure, p.warning, p.caution, p.accent, p.neutral] {
            list.append(("primary/severity badge", p.primaryText, panelTint(tint, theme.badgeTintOpacity, p)))
        }
        for step in PipelineStep.allCases {
            list.append(("black/\(step.rawValue) fill", p.onStageFill, theme.stageColor(step, for: scheme)))
        }
        list.append(("black/failed fill", p.onStageFill, p.failedFill))
        list.append(("black/waiting fill", p.onStageFill, p.waitingFill))
        list.append(("black/burst", p.onStageFill, p.burstFill))
        list.append(("black/burst failed", p.onStageFill, p.failedFill))
        return list
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func everyTextPairReachesAA(scheme: ColorScheme) {
        for (name, text, background) in pairs(scheme) {
            let ratio = text.contrast(against: background)
            #expect(ratio >= minimumContrast, "\(scheme) \(name) = \(ratio)")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func sharedPairsReachAA(scheme: ColorScheme) {
        for pair in theme.allTextPairs(for: scheme) {
            #expect(pair.text.contrast(against: pair.background) >= minimumContrast, "\(scheme) \(pair.name)")
        }
    }
}
