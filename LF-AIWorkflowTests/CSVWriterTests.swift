//
//  CSVWriterTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct CSVWriterTests {
    @Test func plainCellsJoinWithCommas() {
        #expect(CSVWriter.row(["a", "b"]) == "a,b\r\n")
    }

    @Test func quotesCommasQuotesAndNewlines() {
        #expect(CSVWriter.row(["a,b", "say \"hi\"", "l1\nl2"]) == "\"a,b\",\"say \"\"hi\"\"\",\"l1\nl2\"\r\n")
    }

    @Test(arguments: ["=1+1", "+1", "-1", "@SUM(A1)", "\tx", "\rx",
                      "  =1+1", " \t+1", "\n=2", "\u{FF1D}1+1", "\u{FF0B}1", "\u{FF0D}1", "\u{FF20}SUM(A1)"])
    func formulaGuardPrefixesApostrophe(_ cell: String) {
        let row = CSVWriter.row([cell])
        #expect(row.hasPrefix("'") || row.hasPrefix("\"'"))
    }

    @Test func leadingWhitespaceFormulaIsNeutralized() {
        #expect(CSVWriter.row(["  =cmd|' /C calc'!A0"]) == "'  =cmd|' /C calc'!A0\r\n")
    }

    @Test func fullWidthFormulaLeaderIsNeutralized() {
        #expect(CSVWriter.row(["\u{FF1D}HYPERLINK(\"x\")"]) == "\"'\u{FF1D}HYPERLINK(\"\"x\"\")\"\r\n")
    }

    @Test func benignCellUntouched() {
        #expect(CSVWriter.row(["x=1"]) == "x=1\r\n")
    }
}
