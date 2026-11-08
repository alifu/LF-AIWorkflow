//
//  MascotLookTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import Testing
@testable import LF_AIWorkflow

struct MascotLookTests {
    @Test func outlinedStyleStrokesAtTheThemeWidthAsAFractionOfTheSide() {
        let look = MascotLook(style: .outlined, colors: AppTheme.popArt.mascot, outlineWidth: 2.5, size: 24)
        #expect(look.outline == 2.5 / 24)
        #expect(look.showsCheeks)
    }

    @Test func softStyleHasNoOutlineOrCheeks() {
        let look = MascotLook(style: .soft, colors: AppTheme.classic.mascot, outlineWidth: 0, size: 24)
        #expect(look.outline == 0)
        #expect(!look.showsCheeks)
    }

    @Test func outlineScalesWithTheMascotSize() {
        let small = MascotLook(style: .outlined, colors: AppTheme.popArt.mascot, outlineWidth: 2.5, size: 24)
        let large = MascotLook(style: .outlined, colors: AppTheme.popArt.mascot, outlineWidth: 2.5, size: 64)
        #expect(abs(small.outline * 24 - large.outline * 64) < 0.0001)
    }
}
