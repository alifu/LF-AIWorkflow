//
//  HalfCircleShape.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Tab that hangs from the top edge: flat top, half-ellipse bottom (the no-notch collapsed look).
struct HalfCircleShape: Shape {
    private static let kappa: CGFloat = 0.5523   // cubic Bezier approximation of a quarter ellipse

    /// Complexity: O(1) time, O(1) space
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let halfWidth = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * Self.kappa),
                      control2: CGPoint(x: rect.midX + halfWidth * Self.kappa, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                      control1: CGPoint(x: rect.midX - halfWidth * Self.kappa, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * Self.kappa))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HalfCircleShape()
        .fill(.black)
        .frame(width: 130, height: 24)
        .padding()
}
