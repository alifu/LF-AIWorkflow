//
//  ResearchStep.swift
//  LF-AIWorkflow
//

import Foundation

/// Steps shown in a research row. They reuse the existing stage color roles, so no theme token is added.
nonisolated enum ResearchStep: String, Sendable, CaseIterable {
    case capture, clean, extract, analyze, report

    var label: String {
        switch self {
        case .capture: "Capture"
        case .clean: "Clean"
        case .extract: "Extract"
        case .analyze: "Analyze"
        case .report: "Report"
        }
    }

    /// Distinct SF Symbol per step: color is never the only cue.
    var icon: String {
        switch self {
        case .capture: "safari"
        case .clean: "sparkles"
        case .extract: "text.magnifyingglass"
        case .analyze: "brain"
        case .report: "doc.text"
        }
    }

    var colorRole: PipelineStep {
        switch self {
        case .capture: .plan
        case .clean: .test
        case .extract: .fix
        case .analyze: .code
        case .report: .review
        }
    }

    var index: Int { ResearchStep.allCases.firstIndex(of: self) ?? 0 }
}

/// What one chip shows. Shared by the Code and Research pipelines so one view draws both.
nonisolated struct ChipDisplay: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let icon: String
    let marker: String
    let colorRole: PipelineStep
    let status: StageChip.Status
    let accessibilityLabel: String

    init(id: String, label: String, icon: String, marker: String, colorRole: PipelineStep,
         status: StageChip.Status, accessibilityLabel: String? = nil) {
        self.id = id; self.label = label; self.icon = icon; self.marker = marker
        self.colorRole = colorRole; self.status = status
        self.accessibilityLabel = accessibilityLabel ?? "\(label), \(status.spoken)"
    }
}

extension ResearchStep {
    /// Chips for one research task. `reachedIndex` is the last step the task got to (used when it failed or was
    /// cancelled); `extractRan` tells a skipped extract (analysis started without it) from a finished one.
    /// Complexity: O(1) time, O(1) space (five fixed chips)
    nonisolated static func chips(state: ResearchState, reachedIndex: Int, extractRan: Bool) -> [ChipDisplay] {
        let cursor = cursor(state: state, reachedIndex: reachedIndex)
        return allCases.map { step in
            var status: StageChip.Status =
                step.index < cursor.index ? .done : (step.index == cursor.index ? cursor.status : .pending)
            var label = step.label
            if step == .extract, step.index < cursor.index, !extractRan {
                status = .done
                label += " (skipped)"
            }
            return ChipDisplay(id: step.rawValue, label: label, icon: step.icon,
                               marker: StageStyle.marker(status), colorRole: step.colorRole, status: status)
        }
    }

    /// The step a state belongs to, as a chip index; nil for waiting and terminal states.
    nonisolated static func index(for state: ResearchState) -> Int? {
        switch state {
        case .queued, .capture: 0
        case .clean: 1
        case .awaitingPreview, .awaitingInput, .extract: 2
        case .analyze: 3
        case .report: 4
        case .done, .failed, .cancelled: nil
        }
    }

    private nonisolated static func cursor(state: ResearchState, reachedIndex: Int) -> (index: Int, status: StageChip.Status) {
        switch state {
        case .queued: (0, .pending)
        case .capture: (0, .active)
        case .clean: (1, .active)
        case .awaitingPreview, .awaitingInput: (2, .pending)
        case .extract: (2, .active)
        case .analyze: (3, .active)
        case .report: (4, .active)
        case .done: (allCases.count, .done)
        case .failed: (reachedIndex, .failed)
        case .cancelled: (reachedIndex, .pending)
        }
    }
}
