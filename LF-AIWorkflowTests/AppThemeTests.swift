//
//  AppThemeTests.swift
//  LF-AIWorkflowTests
//

import SwiftUI
import Testing
@testable import LF_AIWorkflow

struct AppThemeTests {
    @Test func contrastOfBlackAndWhiteIs21() {
        let ratio = ThemeColor.white(0).contrast(against: .white(1))
        #expect(abs(ratio - 21) < 0.001)
    }

    @Test func contrastIsSymmetricForOpaqueColors() {
        let a = ThemeColor(0.2, 0.4, 0.8), b = ThemeColor(0.9, 0.9, 0.1)
        #expect(abs(a.contrast(against: b) - b.contrast(against: a)) < 0.001)
    }

    @Test func contrastOfEqualColorsIs1() {
        let color = ThemeColor(0.3, 0.6, 0.9)
        #expect(abs(color.contrast(against: color) - 1) < 0.001)
    }

    @Test func translucentTextIsCompositedBeforeContrast() {
        let half = ThemeColor.white(1, alpha: 0.5).contrast(against: .white(0))
        #expect(half > 1 && half < 21)
        #expect(ThemeColor.white(1, alpha: 0).contrast(against: .white(0)) == 1)
    }

    @Test func themeColorEquality() {
        #expect(ThemeColor(0.1, 0.2, 0.3) == ThemeColor(0.1, 0.2, 0.3, 1))
        #expect(ThemeColor(0.1, 0.2, 0.3) != ThemeColor(0.1, 0.2, 0.4))
    }

    @Test func themeFontMapsUppercaseToTextCase() {
        #expect(ThemeFont(size: 10, uppercase: true).textCase == .uppercase)
        #expect(ThemeFont(size: 10).textCase == nil)
    }

    @Test func themeTypesAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(AppTheme.self)
        requireSendable(ThemePalette.self)
        requireSendable(ThemeFont.self)
    }

    @Test func environmentDefaultsToClassic() {
        #expect(EnvironmentValues().appTheme == .classic)
    }

    @Test func paletteSelectsByColorScheme() {
        let theme = AppTheme.classic
        #expect(theme.palette(for: .dark) == theme.darkPalette)
        #expect(theme.palette(for: .light) == theme.lightPalette)
    }
}
