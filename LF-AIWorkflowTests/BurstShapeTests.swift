//
//  BurstShapeTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import LF_AIWorkflow

struct BurstShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 80, height: 40)
    private let tolerance: CGFloat = 0.001

    @Test func defaultBurstHasTwelvePointsAndTwentyFourVertices() {
        #expect(BurstShape().points == 12)
        #expect(BurstShape.vertices(points: 12, innerRatio: 0.7, in: rect).count == 24)
    }

    @Test func verticesStayInsideTheRect() {
        for vertex in BurstShape.vertices(points: 12, innerRatio: 0.7, in: rect) {
            #expect(vertex.x >= rect.minX - tolerance && vertex.x <= rect.maxX + tolerance)
            #expect(vertex.y >= rect.minY - tolerance && vertex.y <= rect.maxY + tolerance)
        }
    }

    @Test func innerVerticesAreCloserToTheCenterThanOuterOnes() {
        let vertices = BurstShape.vertices(points: 12, innerRatio: 0.7, in: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func radius(_ point: CGPoint) -> CGFloat { hypot(point.x - center.x, point.y - center.y) }
        let outer = radius(vertices[0])
        let inner = radius(vertices[1])
        #expect(abs(inner - outer * 0.7) < tolerance)
    }

    @Test func pathStaysWithinTheRectAndIsDeterministic() {
        let shape = BurstShape()
        let bounds = shape.path(in: rect).boundingRect
        #expect(bounds.minX >= rect.minX - tolerance && bounds.maxX <= rect.maxX + tolerance)
        #expect(bounds.minY >= rect.minY - tolerance && bounds.maxY <= rect.maxY + tolerance)
        #expect(shape.path(in: rect).boundingRect == bounds)
    }
}
