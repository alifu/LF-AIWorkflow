//
//  ExtractScriptTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct ExtractScriptTests {
    private func render(_ fixture: String) async throws -> CapturedPage {
        let html = String(decoding: try loadFixture(fixture), as: UTF8.self)
        return try await WebPageRenderer().render(html: html)
    }

    @Test func articleTextOmitsChromeAndScripts() async throws {
        let page = try await render("article.html")
        #expect(page.title == "Fixture Article")
        #expect(page.text.contains("body of the fixture article"))
        for banned in ["SiteHeaderText", "NavHome", "SidebarText", "SiteFooterText", "scripttext", "AriaHiddenText", "DisplayNoneText"] {
            #expect(!page.text.contains(banned), "\(banned)")
        }
        #expect(page.headings == ["Main Heading", "Sub Heading"])
    }

    @Test func onlyHttpLinksKept() async throws {
        let page = try await render("article.html")
        let strings = page.links.map(\.absoluteString)
        #expect(strings.contains("https://example.com/a"))
        #expect(strings.contains { $0.hasSuffix("/rel") })
        #expect(!strings.contains { $0.hasPrefix("javascript:") || $0.hasPrefix("mailto:") })
    }

    @Test func twoTablesWithHeaderRows() async throws {
        let page = try await render("tables.html")
        #expect(page.tables.count == 2)
        #expect(page.tables[0].first == ["Name", "Price"])
        #expect(page.tables[0][2] == ["Beta, Inc", "20"])
        #expect(page.tables[1].first == ["Key", "Value"])
    }

    @Test func formValuesAndPasswordFlag() async throws {
        let page = try await render("login.html")
        #expect(page.hasPasswordField)
        for banned in ["alice-prefilled", "hunter2secret", "textareavalue"] {
            #expect(!page.text.contains(banned))
        }
    }

    @Test func scriptRenderedContentIsCaptured() async throws {
        let page = try await render("spa.html")
        #expect(page.text.contains("Rendered by script"))
    }

    @Test func largestBlockWinsWithoutNav() async throws {
        let page = try await render("nav-heavy.html")
        #expect(page.text.contains("largest text block"))
        #expect(!page.text.contains("NavOne"))
        #expect(!page.text.contains("FooterNav"))
    }
}
