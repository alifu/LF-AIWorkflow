//
//  MascotViewModelTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct MascotViewModelTests {
    private let allPoses: [MascotPose] = [.idle, .typing, .done, .error, .attention]

    @Test func everyPoseDrawsADistinctFrame() {
        let frames = Set(allPoses.map { MascotFrame.frame(for: $0, at: 0.5, reduceMotion: false) })
        #expect(frames.count == allPoses.count)
    }

    @Test func reduceMotionFreezesEveryPoseAcrossTime() {
        for pose in allPoses {
            let atStart = MascotFrame.frame(for: pose, at: 0, reduceMotion: true)
            let later = MascotFrame.frame(for: pose, at: 1.3, reduceMotion: true)
            #expect(atStart == later, "pose \(pose) changed under Reduce Motion")
            #expect(atStart.bob == 0)
            #expect(atStart.eyesClosed == false)
        }
    }

    @Test func reduceMotionSuppressesBlinkInsideTheBlinkWindow() {
        let frame = MascotFrame.frame(for: .idle, at: 0.05, reduceMotion: true)
        #expect(frame.eyesClosed == false)
    }

    @Test func idleBlinksEveryFourSeconds() {
        #expect(MascotFrame.frame(for: .idle, at: 0.05, reduceMotion: false).eyesClosed)
        #expect(MascotFrame.frame(for: .idle, at: 2.0, reduceMotion: false).eyesClosed == false)
        #expect(MascotFrame.frame(for: .idle, at: 4.05, reduceMotion: false).eyesClosed)
    }

    @Test func blinkIsClosedOnlyBrieflyEachCycle() {
        let samples = stride(from: 0.0, to: 4.0, by: 0.01).map {
            MascotFrame.frame(for: .idle, at: $0, reduceMotion: false).eyesClosed
        }
        let closedShare = Double(samples.filter { $0 }.count) / Double(samples.count)
        #expect(closedShare > 0)
        #expect(closedShare <= 0.1)
    }

    @Test func typingBobsAtTwoHertzWithAPeriodOfHalfASecond() {
        let peak = MascotFrame.frame(for: .typing, at: 0.125, reduceMotion: false).bob
        let oneCycleLater = MascotFrame.frame(for: .typing, at: 0.625, reduceMotion: false).bob
        #expect(peak > 0)
        #expect(abs(peak - oneCycleLater) < 1e-9)
    }

    @Test func onlyTypingBobs() {
        for pose in allPoses where pose != .typing {
            #expect(MascotFrame.frame(for: pose, at: 0.125, reduceMotion: false).bob == 0, "pose \(pose) bobs")
        }
    }

    @Test func errorShowsSweatAndAttentionShowsAlert() {
        #expect(MascotFrame.frame(for: .error, at: 0, reduceMotion: false).sweat)
        #expect(MascotFrame.frame(for: .attention, at: 0, reduceMotion: false).alert)
        #expect(MascotFrame.frame(for: .idle, at: 0, reduceMotion: false).sweat == false)
        #expect(MascotFrame.frame(for: .idle, at: 0, reduceMotion: false).alert == false)
    }

    @Test func everyPoseHasAUniqueVoiceOverLabel() {
        let labels = allPoses.map(\.accessibilityLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == allPoses.count)
    }
}
