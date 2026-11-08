//
//  AccessibilityPolicyTests.swift
//  LF-AIWorkflowTests
//

import CoreGraphics
import SwiftUI
import Testing
@testable import LF_AIWorkflow

/// Accessibility rules as pure functions over the environment flags (no pixels).
@MainActor
struct AccessibilityPolicyTests {
    @Test func reduceMotionFreezesTheMascotBobAndBlink() {
        let bobbing = MascotFrame.frame(for: .typing, at: 0.125, reduceMotion: true)
        #expect(bobbing.bob == 0)
        let blinking = MascotFrame.frame(for: .idle, at: 0.05, reduceMotion: true)
        #expect(!blinking.eyesClosed)
    }

    @Test func reduceMotionAlsoRemovesTheBurstAnimation() {
        #expect(CelebrationPolicy.animation(reduceMotion: true) == nil)
        #expect(!CelebrationPolicy.bouncesMascot(reduceMotion: true))
    }

    @Test func reduceTransparencyTurnsOffTheHalftoneOnlyWherePresent() {
        #expect(AppTheme.popArt.showsHalftone(reduceTransparency: false))
        #expect(!AppTheme.popArt.showsHalftone(reduceTransparency: true))
        #expect(!AppTheme.classic.showsHalftone(reduceTransparency: false))
        #expect(!AppTheme.classic.showsHalftone(reduceTransparency: true))
    }

    @Test func everyStageHasAnIconAndALabel() {
        for step in PipelineStep.allCases {
            #expect(!StageStyle.icon(step).isEmpty)
            #expect(!StageStyle.label(step).isEmpty)
        }
        #expect(Set(PipelineStep.allCases.map(StageStyle.icon)).count == PipelineStep.allCases.count)
        #expect(Set(PipelineStep.allCases.map(StageStyle.label)).count == PipelineStep.allCases.count)
    }

    @Test func everyStatusHasADistinctTextMarker() {
        let statuses: [StageChip.Status] = [.pending, .active, .done, .failed]
        let markers = statuses.map(StageStyle.marker)
        #expect(markers.allSatisfy { !$0.isEmpty })
        #expect(Set(markers).count == statuses.count)
    }

    @Test func stageColorIsNeverTheOnlyDifferenceInEitherTheme() {
        for theme in [AppTheme.classic, AppTheme.popArt] {
            for scheme in [ColorScheme.light, .dark] {
                let colors = PipelineStep.allCases.map { theme.stageColor($0, for: scheme) }
                #expect(Set(colors.map { "\($0.r)-\($0.g)-\($0.b)" }).count == colors.count, "\(theme.id) \(scheme)")
            }
        }
    }
}
