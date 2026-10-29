//
//  TextCleanTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

struct TextCleanTests {

    private func page(_ i: Int) throws -> String {
        String(decoding: try loadFixture("page\(i).md"), as: UTF8.self)
    }

    @Test func collapseNormalizesWhitespace() {
        let input = "a \t b  \r\n\n\n\nc\u{01}d   \ne"
        #expect(TextCleaner.collapse(input) == "a b\n\ncd\ne")
    }

    @Test func collapseEmpty() {
        #expect(TextCleaner.collapse("") == "")
        #expect(lf_text_collapse_ws(nil, 5) == 0)
    }

    @Test func hashIsFNV1a() {
        #expect(lf_text_hash(nil, 0) == 14695981039346656037)
        let a = Array("a".utf8)
        #expect(lf_text_hash(a, 1) == 0xaf63dc4c8601ec8c)
    }

    @Test func sharedHeaderFooterRemoved() throws {
        let pages = try (1...4).map(page)
        let r = try TextCleaner.removeBoilerplate(pages)
        #expect(r.removedLines == 8)
        for (i, p) in r.pages.enumerated() {
            #expect(!p.contains("ACME Docs"))
            #expect(!p.contains("Copyright"))
            #expect(p.contains("Unique body \(i + 1) line one."))
            #expect(p.contains("# Page \(i + 1) title"))
        }
    }

    @Test func twoPagesRemoveNothing() throws {
        let pages = [try page(1), try page(2)]
        let r = try TextCleaner.removeBoilerplate(pages)
        #expect(r.removedLines == 0)
        #expect(r.pages == pages)
    }

    @Test func lineRepeatedInOnePageIsNotBoilerplate() throws {
        let pages = ["x\nx\nx\nx\n", "a\n", "b\n", "c\n"]
        let r = try TextCleaner.removeBoilerplate(pages)
        #expect(r.removedLines == 0)
        #expect(r.pages == pages)
    }

    @Test func blankLinesNeverRemoved() throws {
        let pages = ["\n\n  \nA\n", "\n\n  \nB\n", "\n\n  \nC\n"]
        let r = try TextCleaner.removeBoilerplate(pages)
        #expect(r.removedLines == 0)
        #expect(r.pages == pages)
    }

    @Test func exactDuplicatePageFlagged() throws {
        let d = TextCleaner.duplicates(["one", "two", "one", "", "", "two"])
        #expect(d == [nil, nil, 0, nil, 3, 1])
    }

    @Test func emptyInputs() throws {
        #expect(TextCleaner.duplicates([]).isEmpty)
        let r = try TextCleaner.removeBoilerplate([])
        #expect(r.pages.isEmpty && r.removedLines == 0)
        let e = try TextCleaner.removeBoilerplate(["", "", ""])
        #expect(e.pages == ["", "", ""])
        #expect(lf_textclean_dedupe(nil, 1, nil) == -1)
        #expect(lf_textclean_boilerplate(nil, 2, 3, nil, nil, nil) == -1)
    }

    @Test func invalidUTF8SurvivesByteExact() throws {
        let bad: [UInt8] = [0xff, 0xfe, 0x80, 0x0a, 0x41, 0xc3, 0x28, 0x0a]
        let shared: [UInt8] = Array("shared\n".utf8)
        let pages = [shared + bad, shared + [0xfa, 0x0a], shared + [0xfb, 0x0a]]
        let r = try TextCleaner.removeBoilerplateBytes(pages)
        #expect(r.removedLines == 3)
        #expect(r.pages[0] == bad)
        #expect(TextCleaner.collapseBytes(bad) == bad)
    }

    @Test func oneMegabytePage() throws {
        var big = ""
        for i in 0..<20_000 { big += "line number \(i) with some padding text here\n" }
        let pages = [big, big + "x\n", "other\n"]
        let r = try TextCleaner.removeBoilerplate(pages)
        #expect(r.removedLines == 40_000)
        let d = TextCleaner.duplicates([big, big])
        #expect(d == [nil, 0])
        #expect(TextCleaner.collapse(big).utf8.count == big.utf8.count)
    }

    @Test func dedupeRejectsCountThatWouldOverflowTableAllocation() {
        // 2^60 spans: table bytes (cap * 8) would wrap size_t. Must fail before touching memory.
        var span = lf_text_span(ptr: nil, len: 0)
        var dup: [Int] = [0]
        errno = 0
        let rc = lf_textclean_dedupe(&span, 1 << 60, &dup)
        #expect(rc == -1)
        #expect(errno == ENOMEM)
    }
}
