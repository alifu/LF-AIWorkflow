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

    @Test(arguments: ["=1+1", "+1", "-1", "@SUM(A1)", "\tx", "\rx"])
    func formulaGuardPrefixesApostrophe(_ cell: String) {
        let row = CSVWriter.row([cell])
        #expect(row.hasPrefix("'") || row.hasPrefix("\"'"))
    }

    @Test func benignCellUntouched() {
        #expect(CSVWriter.row(["x=1"]) == "x=1\r\n")
    }
}
