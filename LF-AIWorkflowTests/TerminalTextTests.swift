//
//  TerminalTextTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

@Suite struct TerminalTextTests {
    private func lines(_ n: Int) -> [TaskLogLine] {
        (0..<n).map { TaskLogLine(id: $0, stage: .code, text: "line \($0)") }
    }

    @Test func tailKeepsTheNewestLines() {
        let tail = TerminalText.tail(lines(10), limit: 3)
        #expect(tail.map(\.id) == [7, 8, 9])
    }

    @Test func tailLeavesShortLogsAlone() {
        #expect(TerminalText.tail(lines(2), limit: 5).count == 2)
        #expect(TerminalText.tail([], limit: 5).isEmpty)
    }

    @Test func tailWithNonPositiveLimitIsEmpty() {
        #expect(TerminalText.tail(lines(4), limit: 0).isEmpty)
        #expect(TerminalText.tail(lines(4), limit: -2).isEmpty)
    }

    @Test func copyTextJoinsLinesWithNewlines() {
        #expect(TerminalText.copyText(lines(3)) == "line 0\nline 1\nline 2")
        #expect(TerminalText.copyText([]) == "")
    }
}
