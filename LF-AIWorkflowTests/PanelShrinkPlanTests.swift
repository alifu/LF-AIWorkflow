//
//  PanelShrinkPlanTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct PanelShrinkPlanTests {
    @Test func growingAppliesAtOnce() {
        #expect(PanelShrinkPlan.decide(from: .collapsed, to: .expanded, reduceMotion: false) == .applyNow)
        #expect(PanelShrinkPlan.decide(from: .peek, to: .expanded, reduceMotion: false) == .applyNow)
        #expect(PanelShrinkPlan.decide(from: .expanded, to: .pinned, reduceMotion: false) == .applyNow)
    }

    @Test func shrinkingWaitsForTheSpring() {
        #expect(PanelShrinkPlan.decide(from: .expanded, to: .collapsed, reduceMotion: false) == .applyAfter(PanelShrinkPlan.springSettle))
        #expect(PanelShrinkPlan.decide(from: .pinned, to: .peek, reduceMotion: false) == .applyAfter(PanelShrinkPlan.springSettle))
    }

    @Test func reduceMotionShortensTheWait() {
        #expect(PanelShrinkPlan.decide(from: .expanded, to: .collapsed, reduceMotion: true) == .applyAfter(PanelShrinkPlan.reducedMotionSettle))
    }

    @Test func alreadySmallStaysImmediate() {
        #expect(PanelShrinkPlan.decide(from: .collapsed, to: .peek, reduceMotion: false) == .applyNow)
    }

    @Test func peekArrivingMidShrinkStillWaitsForTheFrameOnScreen() {
        var frame = PanelFrameTracker()
        frame.markApplied(.expanded)
        #expect(frame.plan(for: .collapsed, reduceMotion: false) == .applyAfter(PanelShrinkPlan.springSettle))
        // The collapse has been planned but not applied yet, so the frame on screen is still expanded.
        #expect(frame.plan(for: .peek, reduceMotion: false) == .applyAfter(PanelShrinkPlan.springSettle))
    }

    @Test func aShrinkAfterTheFrameWasAppliedIsImmediateWhenSmall() {
        var frame = PanelFrameTracker()
        frame.markApplied(.expanded)
        frame.markApplied(.collapsed)
        #expect(frame.plan(for: .peek, reduceMotion: false) == .applyNow)
    }
}
