//
//  PageCaptureTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct PageCaptureTests {
    private func json(text: String = String(repeating: "word ", count: 80), url: String = "https://example.com/p",
                      tables: String = "[]", links: String = "[]", password: Bool = false) -> String {
        """
        {"v":1,"title":"T","url":"\(url)","text":"\(text)","headings":["H"],"links":\(links),"tables":\(tables),"hasPasswordField":\(password)}
        """
    }

    @Test func parsesValidPage() throws {
        let page = try CapturedPage.parse(json())
        #expect(page.title == "T")
        #expect(page.url.host == "example.com")
    }

    @Test func rejectsMalformedAndBadURL() {
        #expect(throws: CaptureError.malformed) { try CapturedPage.parse("not json") }
        #expect(throws: CaptureError.malformed) { try CapturedPage.parse(json(url: "javascript:alert(1)")) }
        #expect(throws: CaptureError.malformed) { try CapturedPage.parse(json(url: "http://localhost/x")) }
        #expect(throws: CaptureError.malformed) { try CapturedPage.parse(json().replacingOccurrences(of: "\"v\":1", with: "\"v\":2")) }
    }

    @Test func rejectsOversize() {
        let big = String(repeating: "a", count: CapturedPage.maxJSONBytes)
        #expect(throws: CaptureError.tooLarge) { try CapturedPage.parse(json(text: big)) }
        let longText = String(repeating: "a", count: CapturedPage.maxText + 1)
        #expect(throws: CaptureError.tooLarge) { try CapturedPage.parse(json(text: longText)) }
        let manyCols = "[[" + (0..<31).map { _ in "\"c\"" }.joined(separator: ",") + "]]"
        #expect(throws: CaptureError.tooLarge) { try CapturedPage.parse(json(tables: "[\(manyCols)]")) }
    }

    @Test func dropsNonHTTPLinks() throws {
        let page = try CapturedPage.parse(json(links: "[\"https://a.com/x\",\"javascript:1\",\"file:///etc/passwd\"]"))
        #expect(page.links.map(\.absoluteString) == ["https://a.com/x"])
    }

    @Test func saveWritesSourceAndTableCSVs() async throws {
        let root = try TestEnv.makeTempDir()
        let store = ResearchStore(root: root)
        let folder = try await store.createFolder(question: "Q", date: Date(timeIntervalSince1970: 0))
        let tables = "[[[\"a\",\"b\"],[\"1\",\"2\"]],[[\"=x\"]]]"
        let page = try CapturedPage.parse(json(tables: tables))
        let saved = try await PageCapture.save(page, index: 3, store: store, folder: folder)
        #expect(saved.file.lastPathComponent.hasPrefix("03-"))
        #expect(saved.tableFiles.map(\.lastPathComponent) == ["03-1.csv", "03-2.csv"])
        #expect(try String(contentsOf: saved.tableFiles[0], encoding: .utf8) == "a,b\r\n1,2\r\n")
        #expect(saved.tokens > 0)
        #expect(!saved.looksEmpty)
    }

    @Test func looksEmptyForShortOrLoginPages() throws {
        #expect(CapturedPage.looksEmpty(try CapturedPage.parse(json(text: "short"))))
        #expect(CapturedPage.looksEmpty(try CapturedPage.parse(json(password: true))))
    }
}
