//
//  ReportWriterTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct ReportWriterTests {
    private func fixture(_ name: String) throws -> String {
        String(decoding: try loadFixture(name), as: UTF8.self)
    }

    @Test func goodAnswerParsesTableAndCitations() throws {
        let r = ReportWriter.parse(try fixture("answer-good.md"), sourceCount: 2)
        #expect(r.table?.header == ["Product", "Speed", "Price"])
        #expect(r.table?.rows.count == 2)
        #expect(r.table?.rows[1] == ["Beta", "slow [2]", "$5"])
        #expect(r.citations == [1, 2])
        #expect(r.unknownCitations.isEmpty)
        #expect(r.unsourcedCount == 0)
    }

    @Test func answerWithoutTableHasNilTable() throws {
        let r = ReportWriter.parse(try fixture("answer-notable.md"), sourceCount: 1)
        #expect(r.table == nil)
        #expect(r.citations == [1])
    }

    @Test func unknownCitationsAreFlaggedAndUnsourcedCounted() throws {
        let r = ReportWriter.parse(try fixture("answer-badcites.md"), sourceCount: 3)
        #expect(r.unknownCitations == [0, 9])
        #expect(r.citations == [1])
        #expect(r.unsourcedCount == 1)
    }

    @Test func rawHTMLIsEscapedButHTTPAutolinkKept() {
        let r = ReportWriter.parse("Hi <script>alert(1)</script> and <b>x</b> see <https://a.example.com/p> ok [1]", sourceCount: 1)
        #expect(!r.answer.contains("<script>"))
        #expect(!r.answer.contains("<b>"))
        #expect(r.answer.contains("&lt;script>"))
        #expect(r.answer.contains("<https://a.example.com/p>"))
        #expect(ReportWriter.sanitize(r.answer) == r.answer)
    }

    @Test func tableIsCapped() {
        var text = "| " + (0..<40).map { "c\($0)" }.joined(separator: " | ") + " |\n"
        text += "|" + String(repeating: "---|", count: 40) + "\n"
        for i in 0..<300 { text += "| " + (0..<40).map { _ in "\(i)" }.joined(separator: " | ") + " |\n" }
        let t = ReportWriter.parse(text, sourceCount: 1).table
        #expect(t?.header.count == 30)
        #expect(t?.rows.count == 200)
        #expect(t?.rows.first?.count == 30)
    }

    @Test func dangerousLinksAndImagesAreStripped() throws {
        let out = ReportWriter.sanitize(try fixture("answer-injectedlink.md"))
        #expect(!out.contains("file:"))
        #expect(!out.contains("javascript:"))
        #expect(!out.contains("!["))
        #expect(!out.contains("pixel.png"))
        #expect(out.contains("[ok](https://example.com/a)"))
        #expect(out.contains("evil"))
    }

    @Test func controlCharactersAreStripped() {
        let out = ReportWriter.sanitize("a\u{0}b\u{1B}[31mc\u{202E}d\ne\tf")
        #expect(out == "ab[31mcd\ne\tf")
    }

    @Test func renderUsesAppSourcesNotAnswerList() throws {
        let answer = "Alpha [1].\n\nSources\n1. https://evil.example/fake"
        let sources = [ResearchSource(url: "https://real.example/a", title: "Real *A*", body: "")]
        let md = ReportWriter.render(ReportWriter.parse(answer, sourceCount: 1), sources: sources)
        #expect(md.contains("## Sources"))
        #expect(md.contains("https://real.example/a"))
        #expect(md.hasSuffix("\n"))
        let appSection = md.components(separatedBy: "## Sources").last ?? ""
        #expect(!appSection.contains("evil.example"))
    }

    @Test func hugeAnswerIsTruncatedWithNote() {
        let big = String(repeating: "word [1] ", count: 200_000)
        let r = ReportWriter.parse(big, sourceCount: 1)
        #expect(r.answer.utf8.count <= ReportWriter.maxAnswerBytes + 200)
        #expect(r.answer.contains("truncated"))
    }

    @Test func safeMarkdownKeepsOnlyHTTPLinks() throws {
        let a = SafeMarkdown.attributed("[a](https://x.example) [b](file:///x) [c](javascript:1)")
        let links = a.runs.compactMap(\.link)
        #expect(links.map(\.absoluteString) == ["https://x.example"])
    }

    @Test func comparisonCSVRowsAreFormulaGuarded() {
        let t = ComparisonTable(header: ["h"], rows: [["=HYPERLINK(\"x\")"]])
        let csv = CSVWriter.document(t.csvRows)
        #expect(csv.contains("'=HYPERLINK"))
    }
}
