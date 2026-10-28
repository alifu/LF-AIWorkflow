//
//  ErrScanTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

struct ErrScanTests {

    private func opts(before: Int = 2, after: Int = 2, tail: Int = 0, max: Int = 4096) -> ErrorScanner.Options {
        var o = ErrorScanner.Options(maxOutputBytes: max)
        o.contextBefore = before; o.contextAfter = after; o.tailLines = tail
        return o
    }

    private func run(_ log: String, _ o: ErrorScanner.Options) -> (text: String, truncated: Bool) {
        ErrorScanner.extract(Data(log.utf8), options: o)
    }

    private func lines(_ n: Int, prefix: String = "line") -> [String] { (1...n).map { "\(prefix)\($0)" } }

    @Test func emptyLogIsEmpty() {
        #expect(run("", opts()).text.isEmpty)
    }

    @Test func successLogIsEmpty() throws {
        let log = try loadFixture("xcodebuild-success.log")
        let r = ErrorScanner.extract(log, options: opts(tail: 20))
        #expect(r.text.isEmpty)
        #expect(!r.truncated)
    }

    @Test func xcodebuildFixtureHasErrorWithTwoContextLines() throws {
        let log = try loadFixture("xcodebuild-fail.log")
        let r = ErrorScanner.extract(log, options: opts(tail: 0))
        #expect(r.text.contains("error: cannot find 'undefinedValue' in scope"))
        #expect(r.text.contains("cd /Users/dev/App"))                 // 2 lines before
        #expect(r.text.contains("^~~~~~~~~~~~~~"))                    // 2 lines after
        #expect(r.text.contains("BUILD FAILED"))
        #expect(!r.text.contains("Ld step 3"))
    }

    @Test func swiftTestFixtureHasFailureAndContext() throws {
        let log = try loadFixture("swift-test-fail.log")
        let r = ErrorScanner.extract(log, options: opts(tail: 3))
        #expect(r.text.contains("XCTAssertEqual failed"))
        #expect(r.text.contains("Test Case 'MathTests.testAdd' started."))
        #expect(r.text.contains("-- tail --\n"))
        #expect(r.text.hasSuffix("in 0.120 (0.122) seconds\n"))
    }

    @Test func npmFixtureHasFailAndSummary() throws {
        let log = try loadFixture("npm-test-fail.log")
        let r = ErrorScanner.extract(log, options: opts(tail: 2))
        #expect(r.text.contains("FAIL src/sum.test.js"))
        #expect(r.text.contains("sum › adds numbers"))
        #expect(r.text.contains("npm ERR! Test failed."))
    }

    @Test func matchesThreeLinesApartMergeIntoOneGroupWithoutDuplicates() {
        var l = lines(12)
        l[4] = "error: first"; l[7] = "error: second"   // lines 5 and 8
        let r = run(l.joined(separator: "\n") + "\n", opts())
        let out = r.text.split(separator: "\n").map(String.init)
        #expect(!out.contains("--"))
        #expect(out == ["line3", "line4", "error: first", "line6", "line7", "error: second", "line9", "line10"])
    }

    @Test func matchesTenLinesApartFormTwoGroups() {
        var l = lines(30)
        l[4] = "error: a"; l[14] = "error: b"
        let out = run(l.joined(separator: "\n") + "\n", opts()).text.split(separator: "\n").map(String.init)
        #expect(out == ["line3", "line4", "error: a", "line6", "line7", "--",
                        "line13", "line14", "error: b", "line16", "line17"])
    }

    @Test func touchingGroupsMerge() {
        var l = lines(14)
        l[2] = "error: a"; l[7] = "error: b"   // after of a ends at line5(idx4), before of b starts idx5
        let out = run(l.joined(separator: "\n") + "\n", opts()).text.split(separator: "\n").map(String.init)
        #expect(!out.contains("--"))
        #expect(out.count == 10)
    }

    @Test func matchOnFirstAndLastLineClipContext() {
        let l = ["error: first"] + lines(8) + ["error: last"]
        let out = run(l.joined(separator: "\n"), opts()).text.split(separator: "\n").map(String.init)
        #expect(out == ["error: first", "line1", "line2", "--", "line7", "line8", "error: last"])
    }

    @Test func tailOverlappingGroupIsNotDuplicated() {
        var l = lines(10)
        l[8] = "error: near end"
        let r = run(l.joined(separator: "\n") + "\n", opts(tail: 3))
        let out = r.text.split(separator: "\n").map(String.init)
        #expect(out == ["line7", "-- tail --", "line8", "error: near end", "line10"])
        #expect(Set(out).count == out.count)
    }

    @Test func tailOnlyWhenSomethingMatched() {
        #expect(run(lines(30).joined(separator: "\n"), opts(tail: 5)).text.isEmpty)
    }

    @Test func outputCapRespectedExactly() {
        var l = lines(400, prefix: "padding-line-")
        for i in stride(from: 5, to: 400, by: 20) { l[i] = "error: problem number \(i)" }
        let r = run(l.joined(separator: "\n") + "\n", opts(tail: 4, max: 300))
        #expect(r.truncated)
        #expect(r.text.utf8.count <= 300)
        #expect(r.text.hasSuffix("\n"))
        #expect(r.text.contains("error: problem number 5"))     // oldest group first
        #expect(r.text.contains("-- tail --\n"))                // tail reserved
    }

    @Test func singleHugeMatchedLineIsCutToBudget() {
        let huge = "error: " + String(repeating: "é", count: 600_000)   // > 1 MiB
        let r = run(huge, opts(tail: 0, max: 1000))
        #expect(r.truncated)
        #expect(r.text.utf8.count <= 1000)
        #expect(r.text.hasPrefix("error: é"))
        #expect(!r.text.contains("\u{FFFD}"))                          // cut on a UTF-8 boundary
    }

    @Test func hugeLineInTailIsCutToTailBudget() {
        let huge = "error: " + String(repeating: "日", count: 100_000)
        let r = run("start\n" + huge, opts(tail: 5, max: 1000))
        #expect(r.truncated)
        #expect(r.text.utf8.count <= 1000)
        #expect(!r.text.contains("\u{FFFD}"))
    }

    @Test func tailDropsOldestLinesWhenOverBudget() {
        var l = lines(50, prefix: "some-long-padding-line-")
        l[0] = "error: early"
        let r = run(l.joined(separator: "\n") + "\n", opts(before: 0, after: 0, tail: 40, max: 200))
        #expect(r.truncated)
        #expect(r.text.utf8.count <= 200)
        #expect(r.text.hasSuffix("some-long-padding-line-50\n"))
    }

    @Test func crlfLogIsNormalized() {
        let r = run("a\r\nerror: boom\r\nb\r\n", opts())
        #expect(r.text == "a\nerror: boom\nb\n")
    }

    @Test func missingTrailingNewlineStillMatches() {
        #expect(run("x\nerror: end", opts()).text == "x\nerror: end\n")
    }

    @Test func invalidUTF8AroundMatchIsRepaired() {
        var d = Data([0xFF, 0xFE, 0x0A])
        d.append(Data("error: bad \u{0}\n".utf8))
        d.append(Data([0xE3, 0x81, 0x0A]))
        let r = ErrorScanner.extract(d, options: opts())
        #expect(r.text.contains("error: bad"))
        #expect(String(data: Data(r.text.utf8), encoding: .utf8) != nil)
    }

    @Test func ansiColoredErrorStillMatches() {
        #expect(run("\u{1B}[31merror:\u{1B}[0m something\n", opts()).text.contains("something"))
    }

    @Test(arguments: ["Error: x", "FATAL ERROR", "Tests failed", "FAIL src/a.test.js", "✘ test", "build FAILED", "fatal: bad"])
    func patternsMatch(line: String) {
        #expect(!run("ok\n\(line)\nok\n", opts()).text.isEmpty)
    }

    @Test(arguments: ["0 errors", "errors=0", "error", "Fail", "all good ✔"])
    func nonMatchesStayEmpty(line: String) {
        #expect(run("ok\n\(line)\nok\n", opts()).text.isEmpty)
    }

    @Test func invalidArgumentsFailWithEINVAL() {
        var out = [CChar](repeating: 0, count: 8)
        var o = lf_errscan_default_options(8)
        errno = 0
        #expect(lf_errscan_extract("x", 1, nil, &out, 8, nil) == -1)
        #expect(errno == EINVAL)
        o.max_output_bytes = 0
        #expect(lf_errscan_extract("x", 1, &o, &out, 8, nil) == -1)
        o.max_output_bytes = 16
        #expect(lf_errscan_extract("x", 1, &o, &out, 8, nil) == -1)   // out_cap < budget
        #expect(lf_errscan_extract(nil, 3, &o, &out, 8, nil) == -1)
        #expect(lf_errscan_default_options(5).tail_lines == 20)
    }

    @Test func tinyBudgetNeverOverflows() {
        for cap in 1...14 {
            let r = run("a\nerror: boom\nb\n", opts(tail: 3, max: cap))
            #expect(r.text.utf8.count <= cap)
        }
    }

    @Test func zeroBudgetOptionReturnsEmpty() {
        #expect(run("error: x", opts(max: 0)).text.isEmpty)
    }
}
