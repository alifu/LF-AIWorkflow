//
//  PanelChromeGeometryTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import LF_AIWorkflow

/// TD-060: the panel's outline and hard shadow must fit inside the fixed panel frame, or the frame clips them.
struct PanelChromeGeometryTests {
    private let frame = CGRect(x: 0, y: 0, width: 560, height: 400)

    @Test func popArtOutlineAndHardShadowFitInsideTheFrame() {
        let theme = AppTheme.popArt
        let shape = PanelChromeGeometry.shapeRect(in: frame, outlineWidth: theme.outlineWidth, shadow: theme.shadow)
        let half = theme.outlineWidth / 2
        let outline = shape.insetBy(dx: -half, dy: -half)
        #expect(frame.contains(outline))
        if let shadow = theme.shadow {
            let shadowShape = shape.offsetBy(dx: shadow.dx, dy: shadow.dy).insetBy(dx: -half, dy: -half)
            #expect(frame.contains(shadowShape))
        }
    }

    @Test func popArtShapeLeavesTheShadowGutterOnTrailingAndBottom() {
        let theme = AppTheme.popArt
        let shape = PanelChromeGeometry.shapeRect(in: frame, outlineWidth: theme.outlineWidth, shadow: theme.shadow)
        let gutterRight = frame.maxX - shape.maxX
        let gutterBottom = frame.maxY - shape.maxY
        #expect(gutterRight >= (theme.shadow?.dx ?? 0))
        #expect(gutterBottom >= (theme.shadow?.dy ?? 0))
    }

    @Test func classicNeedsNoRoomSoItFillsTheFrame() {
        let theme = AppTheme.classic
        let shape = PanelChromeGeometry.shapeRect(in: frame, outlineWidth: theme.outlineWidth, shadow: theme.shadow)
        #expect(shape == frame)
    }

    @Test func themeInsetCoversTheChromeInEveryTheme() {
        for theme in [AppTheme.classic, AppTheme.popArt] {
            #expect(theme.panelInset >= theme.minimumPanelInset)
        }
    }
}
