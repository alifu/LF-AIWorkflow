//
//  ResearchTransitions.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum ResearchState: String, Sendable, Equatable, CaseIterable {
    case queued, capture, clean, awaitingPreview, extract, analyze, report, done, failed, cancelled, awaitingInput
}

nonisolated enum ResearchEvent: Sendable, Equatable, CaseIterable {
    case begin, captured, cleaned, startExtract, startAnalyze, extracted, analyzed, reported
    case needInput, retry, followUp, fail, cancel
}

/// Pure transition table. `nil` means the move is illegal.
nonisolated enum ResearchTransitions {
    private static let live: Set<ResearchState> = [
        .queued, .capture, .clean, .awaitingPreview, .extract, .analyze, .report, .awaitingInput,
    ]

    /// Complexity: O(1) time, O(1) space
    static func next(_ state: ResearchState, _ event: ResearchEvent) -> ResearchState? {
        if event == .fail { return live.contains(state) ? .failed : nil }
        if event == .cancel { return live.contains(state) ? .cancelled : nil }
        switch (state, event) {
        case (.queued, .begin): return .capture
        case (.capture, .captured): return .clean
        case (.clean, .cleaned): return .awaitingPreview
        case (.awaitingPreview, .startExtract): return .extract
        case (.awaitingPreview, .startAnalyze): return .analyze
        case (.awaitingPreview, .needInput): return .awaitingInput
        case (.awaitingInput, .retry): return .awaitingPreview
        case (.extract, .extracted): return .analyze
        case (.analyze, .analyzed): return .report
        case (.report, .reported): return .done
        case (.done, .followUp): return .analyze
        default: return nil
        }
    }
}
