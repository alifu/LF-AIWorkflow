//
//  BurstShape.swift
//  LF-AIWorkflow
//

import SwiftUI

/// A comic "burst" star behind the celebration word. Deterministic: the same rect always gives the same vertices.
nonisolated struct BurstShape: Shape {
    /// Minimum spikes: fewer than three cannot form a star.
    static let minimumPoints = 3

    var points: Int = 12
    var innerRatio: CGFloat = 0.7

    /// The 2 * points vertices, alternating outer and inner, starting at the top. Points below the minimum are clamped.
    /// Complexity: O(p) time, O(p) space (p = points)
    static func vertices(points: Int, innerRatio: CGFloat, in rect: CGRect) -> [CGPoint] {
        let count = max(minimumPoints, points)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let step = CGFloat.pi / CGFloat(count)
        return (0..<(2 * count)).map { index in
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * step
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    /// Complexity: O(p) time, O(p) space (p = points)
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vertices = Self.vertices(points: points, innerRatio: innerRatio, in: rect)
        guard let first = vertices.first else { return path }
        path.move(to: first)
        for vertex in vertices.dropFirst() { path.addLine(to: vertex) }
        path.closeSubpath()
        return path
    }
}
