//
//  TaskStatusLineTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

@MainActor
struct TaskStatusLineTests {
    @Test func solidThemeShowsAnAttentionStatusAsAPill() {
        #expect(TaskStatusLine.style(needsAttention: true, fills: .solid) == .pill)
    }

    @Test func tintedThemeKeepsAnAttentionStatusAsColoredText() {
        #expect(TaskStatusLine.style(needsAttention: true, fills: .tint) == .attentionText)
    }

    @Test func statusWithoutAttentionIsPlainTextInEveryTheme() {
        #expect(TaskStatusLine.style(needsAttention: false, fills: .solid) == .plainText)
        #expect(TaskStatusLine.style(needsAttention: false, fills: .tint) == .plainText)
    }
}
