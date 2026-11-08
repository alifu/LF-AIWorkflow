//
//  MascotShapes.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Draws a `MascotFrame` with paths. Geometry is in fractions of the square side, so it scales from 18 pt to 64 pt.
enum MascotShapes {
    /// Complexity: O(1) time, O(1) space (a fixed number of paths)
    static func draw(_ frame: MascotFrame, in context: inout GraphicsContext, size: CGSize, look: MascotLook) {
        let colors = look.colors
        let side = min(size.width, size.height)
        let unit = { (value: CGFloat) in value * side }
        let bob = unit(frame.bob)
        let face = CGRect(x: unit(0.08), y: unit(0.08) + bob, width: unit(0.84), height: unit(0.84))

        context.fill(Path(ellipseIn: face), with: .color(colors.face.color))
        if look.showsCheeks { drawCheeks(bob: bob, unit: unit, colors: colors, in: &context) }
        if look.outline > 0 {
            context.stroke(Path(ellipseIn: face), with: .color(colors.features.color), lineWidth: unit(look.outline))
        }
        drawEyes(frame.eyesClosed, bob: bob, unit: unit, colors: colors, in: &context)
        drawMouth(frame.mouth, bob: bob, unit: unit, colors: colors, in: &context)
        if frame.sweat { drawSweat(unit: unit, colors: colors, in: &context) }
        if frame.alert { drawAlert(unit: unit, colors: colors, in: &context) }
        if frame.paper { drawPaper(bob: bob, unit: unit, colors: colors, in: &context) }
    }

    /// Two halftone-style dots on the cheeks (Pop Art shading).
    /// Complexity: O(1) time, O(1) space
    private static func drawCheeks(bob: CGFloat, unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        for centerX in [CGFloat(0.22), 0.78] {
            let dot = CGRect(x: unit(centerX) - unit(0.035), y: unit(0.56) + bob - unit(0.035),
                             width: unit(0.07), height: unit(0.07))
            context.fill(Path(ellipseIn: dot), with: .color(colors.features.fading(0.35).color))
        }
    }

    /// Complexity: O(1) time, O(1) space
    private static func drawEyes(_ closed: Bool, bob: CGFloat, unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        for centerX in [CGFloat(0.36), 0.64] {
            let x = unit(centerX)
            let y = unit(0.42) + bob
            if closed {
                var line = Path()
                line.move(to: CGPoint(x: x - unit(0.06), y: y))
                line.addLine(to: CGPoint(x: x + unit(0.06), y: y))
                context.stroke(line, with: .color(colors.features.color),
                               style: StrokeStyle(lineWidth: unit(0.04), lineCap: .round))
            } else {
                context.fill(Path(ellipseIn: CGRect(x: x - unit(0.05), y: y - unit(0.05),
                                                    width: unit(0.1), height: unit(0.1))),
                             with: .color(colors.features.color))
            }
        }
    }

    /// Complexity: O(1) time, O(1) space
    private static func drawMouth(_ mouth: MouthShape, bob: CGFloat, unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        let left = CGPoint(x: unit(0.36), y: unit(0.6) + bob)
        let right = CGPoint(x: unit(0.64), y: unit(0.6) + bob)
        switch mouth {
        case .smile:
            var curve = Path()
            curve.move(to: left)
            curve.addQuadCurve(to: right, control: CGPoint(x: unit(0.5), y: unit(0.74) + bob))
            context.stroke(curve, with: .color(colors.features.color),
                           style: StrokeStyle(lineWidth: unit(0.04), lineCap: .round))
        case .grin:
            var shape = Path()
            shape.move(to: CGPoint(x: unit(0.34), y: unit(0.6) + bob))
            shape.addQuadCurve(to: CGPoint(x: unit(0.66), y: unit(0.6) + bob),
                               control: CGPoint(x: unit(0.5), y: unit(0.82) + bob))
            shape.closeSubpath()
            context.fill(shape, with: .color(colors.features.color))
        case .flat:
            var line = Path()
            line.move(to: CGPoint(x: unit(0.38), y: unit(0.66) + bob))
            line.addLine(to: CGPoint(x: unit(0.62), y: unit(0.66) + bob))
            context.stroke(line, with: .color(colors.features.color),
                           style: StrokeStyle(lineWidth: unit(0.04), lineCap: .round))
        case .open:
            context.fill(Path(ellipseIn: CGRect(x: unit(0.44), y: unit(0.6) + bob,
                                                width: unit(0.12), height: unit(0.14))),
                         with: .color(colors.features.color))
        }
    }

    /// Complexity: O(1) time, O(1) space
    private static func drawSweat(unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: unit(0.78), y: unit(0.16), width: unit(0.12), height: unit(0.12))),
                     with: .color(colors.sweat.color))
    }

    /// An exclamation mark in the top-right corner.
    /// Complexity: O(1) time, O(1) space
    private static func drawAlert(unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        context.fill(Path(roundedRect: CGRect(x: unit(0.84), y: unit(0.02), width: unit(0.06), height: unit(0.2)),
                          cornerRadius: unit(0.03)),
                     with: .color(colors.alert.color))
        context.fill(Path(ellipseIn: CGRect(x: unit(0.83), y: unit(0.26), width: unit(0.08), height: unit(0.08))),
                     with: .color(colors.alert.color))
    }

    /// A sheet with two text lines held at the lower right (Reading pose). Static, so Reduce Motion needs no special case.
    /// Complexity: O(1) time, O(1) space
    private static func drawPaper(bob: CGFloat, unit: (CGFloat) -> CGFloat, colors: MascotColors, in context: inout GraphicsContext) {
        let sheet = CGRect(x: unit(0.56), y: unit(0.62) + bob, width: unit(0.34), height: unit(0.34))
        context.fill(Path(roundedRect: sheet, cornerRadius: unit(0.03)), with: .color(colors.face.color))
        context.stroke(Path(roundedRect: sheet, cornerRadius: unit(0.03)), with: .color(colors.features.color),
                       lineWidth: unit(0.03))
        for lineY in [CGFloat(0.72), 0.82] {
            var line = Path()
            line.move(to: CGPoint(x: unit(0.61), y: unit(lineY) + bob))
            line.addLine(to: CGPoint(x: unit(0.85), y: unit(lineY) + bob))
            context.stroke(line, with: .color(colors.features.color),
                           style: StrokeStyle(lineWidth: unit(0.025), lineCap: .round))
        }
    }
}
