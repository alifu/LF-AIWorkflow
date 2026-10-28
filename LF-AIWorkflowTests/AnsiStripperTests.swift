//
//  AnsiStripperTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct AnsiStripperTests {
    @Test func plainTextIsUnchanged() {
        #expect(AnsiStripper.strip("hello world\nline 2") == "hello world\nline 2")
    }

    @Test func removesColorCodes() {
        #expect(AnsiStripper.strip("\u{1B}[31mred\u{1B}[0m ok") == "red ok")
        #expect(AnsiStripper.strip("\u{1B}[1;38;5;196mbold\u{1B}[m") == "bold")
    }

    @Test func removesCursorMovesAndErase() {
        #expect(AnsiStripper.strip("a\u{1B}[2K\u{1B}[1Gb\u{1B}[10;5Hc") == "abc")
        #expect(AnsiStripper.strip("\u{1B}[?25lhidden\u{1B}[?25h") == "hidden")
    }

    @Test func removesOSCTerminatedByBelOrST() {
        #expect(AnsiStripper.strip("\u{1B}]0;title\u{07}text") == "text")
        #expect(AnsiStripper.strip("\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\") == "link")
    }

    @Test func removesTwoByteEscapes() {
        #expect(AnsiStripper.strip("\u{1B}7saved\u{1B}8") == "saved")
    }

    @Test func danglingEscapeAtEndIsDropped() {
        #expect(AnsiStripper.strip("text\u{1B}") == "text")
        #expect(AnsiStripper.strip("text\u{1B}[31") == "text")
    }

    @Test func keepsUnicode() {
        #expect(AnsiStripper.strip("\u{1B}[32m✓ passed — ok\u{1B}[0m") == "✓ passed — ok")
    }
}
