//
//  ComicBubble.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Speech bubble whose tail sits on the left edge at mid height and points at the mascot beside it.
nonisolated struct ComicBubble: Shape {
    static let defaultTailLength: CGFloat = 10
    /// Half the tail's height where it meets the bubble.
    static let tailHalfHeight: CGFloat = 6

    let cornerRadius: CGFloat
    let tailLength: CGFloat

    /// The tail tip: left edge, mid height.
    /// Complexity: O(1) time, O(1) space
    func tailTip(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX, y: rect.midY)
    }

    /// One closed outline (tail and rounded body), so a stroke draws no seam at the tail.
    /// Complexity: O(1) time, O(1) space
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX + tailLength, y: rect.minY,
                          width: max(0, rect.width - tailLength), height: rect.height)
        let radius = min(cornerRadius, body.width / 2, body.height / 2)
        let tip = tailTip(in: rect)
        var path = Path()
        path.move(to: CGPoint(x: body.minX, y: tip.y - Self.tailHalfHeight))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: body.minX, y: tip.y + Self.tailHalfHeight))
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX + radius, y: body.maxY), radius: radius)
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.maxX, y: body.maxY - radius), radius: radius)
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY + radius))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX - radius, y: body.minY), radius: radius)
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX, y: body.minY + radius), radius: radius)
        path.closeSubpath()
        return path
    }
}
