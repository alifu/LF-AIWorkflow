//
//  ComicBubbleTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import LF_AIWorkflow

struct ComicBubbleTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
    private let bubble = ComicBubble(cornerRadius: 6, tailLength: ComicBubble.defaultTailLength)

    @Test func tailTipSitsOnTheLeftEdgeAtMidHeight() {
        let tip = bubble.tailTip(in: rect)
        #expect(tip.x == rect.minX)
        #expect(tip.y == rect.midY)
    }

    @Test func pathReachesTheTailTipAndStaysInTheRect() {
        let bounds = bubble.path(in: rect).boundingRect
        #expect(bounds.minX == bubble.tailTip(in: rect).x)
        #expect(bounds.maxX == rect.maxX)
        #expect(bounds.minY == rect.minY)
        #expect(bounds.maxY == rect.maxY)
    }

    @Test func bodyIsInsetByTheTailLength() {
        let bounds = bubble.path(in: rect).boundingRect
        #expect(bounds.minX + ComicBubble.defaultTailLength <= rect.maxX)
        #expect(bounds.width == rect.width)
    }
}
