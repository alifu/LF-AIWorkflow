//
//  DraftTitleTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

@Suite struct DraftTitleTests {
    @Test func usesTheFirstNonEmptyLineTrimmed() {
        #expect(DraftTitle.derive(from: "\n  Add login form  \nwith biometrics") == "Add login form")
    }

    @Test func capsLongTitles() {
        let title = DraftTitle.derive(from: String(repeating: "a", count: 200))
        #expect(title.count == DraftTitle.maxLength)
    }

    @Test func emptyPromptGetsAPlaceholder() {
        #expect(DraftTitle.derive(from: "  \n \n") == "Untitled task")
        #expect(DraftTitle.derive(from: "") == "Untitled task")
    }

    @Test func doesNotSplitAGraphemeCluster() {
        let family = "👨‍👩‍👧"
        let title = DraftTitle.derive(from: String(repeating: family, count: 70))
        #expect(title.count == DraftTitle.maxLength)
        #expect(title.hasSuffix(family))
    }
}
