//
//  CelebrationPolicyTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct CelebrationPolicyTests {
    @Test func doneBurstsDone() {
        #expect(CelebrationPolicy.label(for: .done) == "DONE!")
    }

    @Test func failedBurstsOops() {
        #expect(CelebrationPolicy.label(for: .failed) == "OOPS!")
    }

    @Test func pendingAndActiveDoNotBurst() {
        #expect(CelebrationPolicy.label(for: .pending) == nil)
        #expect(CelebrationPolicy.label(for: .active) == nil)
    }

    @Test func burstStaysForOnePointTwoSeconds() {
        #expect(CelebrationPolicy.duration == .milliseconds(1200))
    }

    @Test func reduceMotionRemovesTheAnimation() {
        #expect(CelebrationPolicy.animation(reduceMotion: true) == nil)
        #expect(CelebrationPolicy.animation(reduceMotion: false) != nil)
    }

    @Test func reduceMotionStopsBouncing() {
        #expect(!CelebrationPolicy.bouncesMascot(reduceMotion: true))
        #expect(CelebrationPolicy.bouncesMascot(reduceMotion: false))
    }
}
