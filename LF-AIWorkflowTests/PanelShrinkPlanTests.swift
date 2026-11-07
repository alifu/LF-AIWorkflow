//
//  PanelShrinkPlanTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct PanelShrinkPlanTests {
    @Test func growingAppliesAtOnce() {
        #expect(PanelShrinkPlan.decide(from: .collapsed, to: .expanded) == .applyNow)
        #expect(PanelShrinkPlan.decide(from: .peek, to: .expanded) == .applyNow)
        #expect(PanelShrinkPlan.decide(from: .expanded, to: .pinned) == .applyNow)
    }

    @Test func shrinkingWaitsForTheAnimationToEnd() {
        #expect(PanelShrinkPlan.decide(from: .expanded, to: .collapsed) == .awaitAnimationEnd)
        #expect(PanelShrinkPlan.decide(from: .pinned, to: .peek) == .awaitAnimationEnd)
    }

    @Test func alreadySmallStaysImmediate() {
        #expect(PanelShrinkPlan.decide(from: .collapsed, to: .peek) == .applyNow)
    }

    @Test func growingReturnsTheStateToApplyAtOnce() {
        var frame = PanelFrameTracker()
        #expect(frame.request(.expanded) == .expanded)
        #expect(frame.appliedState == .expanded)
    }

    @Test func shrinkingAppliesOnlyWhenTheAnimationFinishesAndOnlyOnce() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        #expect(frame.request(.collapsed) == nil)
        #expect(frame.appliedState == .expanded)
        #expect(frame.animationFinished(.collapsed) == .collapsed)
        #expect(frame.appliedState == .collapsed)
        #expect(frame.animationFinished(.collapsed) == nil)
    }

    @Test func openToCollapsedToPeekKeepsTheShrinkBeforeThePeek() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        #expect(frame.request(.collapsed) == nil)
        // The collapse has not reached the frame yet, so the peek is still a shrink from the open frame.
        #expect(frame.request(.peek) == nil)
        // The superseded collapse finishing must not apply a stale frame.
        #expect(frame.animationFinished(.collapsed) == nil)
        #expect(frame.animationFinished(.peek) == .peek)
        #expect(frame.appliedState == .peek)
    }

    @Test func aSmallStateChangeAfterTheFrameWasAppliedIsImmediate() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        _ = frame.request(.collapsed)
        _ = frame.animationFinished(.collapsed)
        #expect(frame.request(.peek) == .peek)
    }

    @Test func growingCancelsAPendingShrink() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        _ = frame.request(.collapsed)
        #expect(frame.request(.expanded) == .expanded)
        #expect(frame.animationFinished(.collapsed) == nil)
    }

    @Test func noCompletionAppliesThePendingShrinkAtTheDeadline() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        _ = frame.request(.collapsed)
        #expect(frame.deadlineReached(.collapsed) == .collapsed)
        #expect(frame.appliedState == .collapsed)
    }

    @Test func completionBeforeTheDeadlineAppliesOnceAndTheDeadlineIsIgnored() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        _ = frame.request(.collapsed)
        #expect(frame.animationFinished(.collapsed) == .collapsed)
        #expect(frame.deadlineReached(.collapsed) == nil)
    }

    @Test func aNewRequestSupersedesTheDeadlineOfTheOlderShrink() {
        var frame = PanelFrameTracker()
        _ = frame.request(.expanded)
        _ = frame.request(.collapsed)
        _ = frame.request(.peek)
        #expect(frame.deadlineReached(.collapsed) == nil)
        #expect(frame.deadlineReached(.peek) == .peek)
        #expect(PanelShrinkPlan.fallbackDeadline == .seconds(1))
    }
}
