//
//  ArtStylePreviewTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

@MainActor
struct ArtStylePreviewTests {
    @Test func classicStyleCandidatesUseTheClassicTheme() {
        #expect(ArtStylePreviewCandidates.theme(for: .classic).id == .classic)
    }

    @Test func popArtStyleCandidatesUseThePopArtTheme() {
        #expect(ArtStylePreviewCandidates.theme(for: .popArt).id == .popArt)
    }

    @Test func candidatesCoverEveryStyleInPickerOrder() {
        let candidates = ArtStylePreviewCandidates.candidates()
        #expect(candidates.map(\.style) == ArtStyle.allCases)
        #expect(candidates.allSatisfy { $0.theme.id == $0.style })
    }

    @Test func styleTitlesAreNonEmptyAndDistinct() {
        let titles = ArtStyle.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == ArtStyle.allCases.count)
    }
}
