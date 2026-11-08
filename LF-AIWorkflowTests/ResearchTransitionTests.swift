//
//  ResearchTransitionTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct ResearchTransitionTests {
    @Test func happyPathWalksEveryState() {
        let path: [(ResearchState, ResearchEvent, ResearchState)] = [
            (.queued, .begin, .capture), (.capture, .captured, .clean), (.clean, .cleaned, .awaitingPreview),
            (.awaitingPreview, .startExtract, .extract), (.extract, .extracted, .analyze),
            (.awaitingPreview, .startAnalyze, .analyze), (.analyze, .analyzed, .report), (.report, .reported, .done),
            (.awaitingPreview, .needInput, .awaitingInput), (.awaitingInput, .retry, .awaitingPreview),
            (.done, .followUp, .analyze),
        ]
        for (from, event, to) in path {
            #expect(ResearchTransitions.next(from, event) == to)
        }
    }

    @Test func failAndCancelWorkFromEveryLiveState() {
        let live: [ResearchState] = [.queued, .capture, .clean, .awaitingPreview, .extract, .analyze, .report, .awaitingInput]
        for state in live {
            #expect(ResearchTransitions.next(state, .fail) == .failed)
            #expect(ResearchTransitions.next(state, .cancel) == .cancelled)
        }
    }

    @Test func terminalStatesAcceptNothing() {
        for state in [ResearchState.failed, .cancelled] {
            for event in ResearchEvent.allCases {
                #expect(ResearchTransitions.next(state, event) == nil)
            }
        }
        #expect(ResearchTransitions.next(.done, .cancel) == nil)
        #expect(ResearchTransitions.next(.done, .fail) == nil)
    }

    @Test func illegalJumpsAreRejected() {
        #expect(ResearchTransitions.next(.queued, .startAnalyze) == nil)
        #expect(ResearchTransitions.next(.capture, .startExtract) == nil)
        #expect(ResearchTransitions.next(.clean, .startAnalyze) == nil)
        #expect(ResearchTransitions.next(.awaitingPreview, .analyzed) == nil)
        #expect(ResearchTransitions.next(.analyze, .followUp) == nil)
        #expect(ResearchTransitions.next(.done, .begin) == nil)
    }
}
