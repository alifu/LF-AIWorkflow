//
//  NotchShapeTests.swift
//  LF-AIWorkflowTests
//

import Testing
import SwiftUI
@testable import LF_AIWorkflow

@MainActor
@Suite struct NotchShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func pathStaysInsideTheRect() {
        let bounds = NotchShape(bottomRadius: 20).path(in: rect).boundingRect
        #expect(bounds.minX >= -0.001 && bounds.minY >= -0.001)
        #expect(bounds.maxX <= rect.maxX + 0.001 && bounds.maxY <= rect.maxY + 0.001)
        #expect(abs(bounds.width - 200) < 0.5 && abs(bounds.height - 100) < 0.5)
    }

    @Test func topEdgeIsFlatAndFullWidth() {
        let path = NotchShape(bottomRadius: 20).path(in: rect)
        #expect(path.contains(CGPoint(x: 1, y: 0.5)))
        #expect(path.contains(CGPoint(x: 199, y: 0.5)))
        // The bottom corners are cut away.
        #expect(!path.contains(CGPoint(x: 0.5, y: 99.5)))
        #expect(path.contains(CGPoint(x: 100, y: 99.5)))
    }

    @Test func radiusIsClampedToHalfTheHeight() {
        let huge = NotchShape(bottomRadius: 10_000).path(in: rect).boundingRect
        #expect(huge.maxY <= rect.maxY + 0.001 && huge.maxX <= rect.maxX + 0.001)
        let negative = NotchShape(bottomRadius: -5).path(in: rect).boundingRect
        #expect(abs(negative.height - 100) < 0.5)
    }

    @Test func emptyRectGivesEmptyPath() {
        #expect(NotchShape(bottomRadius: 8).path(in: .zero).isEmpty)
    }

    @Test func radiusAnimates() {
        var shape = NotchShape(bottomRadius: 4)
        shape.animatableData = 12
        #expect(shape.bottomRadius == 12)
    }
}

@MainActor
@Suite struct HalfCircleShapeTests {
    @Test func pathFillsTheRectAndHangsFromTheTop() {
        let rect = CGRect(x: 0, y: 0, width: 130, height: 24)
        let path = HalfCircleShape().path(in: rect)
        let bounds = path.boundingRect
        #expect(abs(bounds.width - 130) < 0.5 && abs(bounds.height - 24) < 0.5)
        #expect(path.contains(CGPoint(x: 65, y: 12)))
        #expect(path.contains(CGPoint(x: 1, y: 0.5)))
        #expect(!path.contains(CGPoint(x: 1, y: 23)))
    }

    @Test func emptyRectGivesEmptyPath() {
        #expect(HalfCircleShape().path(in: .zero).isEmpty)
    }
}
