//
//  StageStyleTests.swift
//  LF-AIWorkflowTests
//

import SwiftUI
import Testing
@testable import LF_AIWorkflow

@MainActor
@Suite struct StageStyleTests {
    @Test func everyStepHasADistinctNonEmptyIconAndLabel() {
        let icons = PipelineStep.allCases.map(StageStyle.icon)
        let labels = PipelineStep.allCases.map(StageStyle.label)
        #expect(icons.allSatisfy { !$0.isEmpty } && Set(icons).count == icons.count)
        #expect(labels.allSatisfy { !$0.isEmpty } && Set(labels).count == labels.count)
    }

    @Test func labelsMatchTheChipVocabulary() {
        #expect(PipelineStep.allCases.map(StageStyle.label) == ["Plan", "Code", "Test", "Fix", "Review"])
    }

    @Test func statusMarkersAreNotColorOnly() {
        let marks = [StageChip.Status.pending, .active, .done, .failed].map(StageStyle.marker)
        #expect(Set(marks).count == 4 && marks.allSatisfy { !$0.isEmpty })
    }

    @Test func colorComesFromTheThemeForEachScheme() {
        for step in PipelineStep.allCases {
            #expect(StageStyle.color(step, theme: .classic, scheme: .dark) == AppTheme.classic.stageColor(step, for: .dark).color)
            #expect(StageStyle.color(step, theme: .classic, scheme: .light) == AppTheme.classic.stageColor(step, for: .light).color)
        }
    }
}

