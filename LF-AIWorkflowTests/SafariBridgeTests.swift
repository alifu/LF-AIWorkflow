//
//  SafariBridgeTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private actor Recorder {
    var calls: [ProcessInvocation] = []
    var timeouts: [Duration] = []
    var caps: [Int] = []
    func add(_ i: ProcessInvocation, _ t: Duration, _ c: Int) { calls.append(i); timeouts.append(t); caps.append(c) }
}

private func result(_ status: Int32 = 0, out: Data = Data(), err: Data = Data(), truncated: Bool = false) -> CommandResult {
    CommandResult(status: status, stdout: out, stderr: err, truncated: truncated)
}

private let scriptURL = URL(fileURLWithPath: "/tmp/safari-bridge.js")
private let extractURL = URL(fileURLWithPath: "/tmp/extract.js")

private func bridge(_ rec: Recorder, _ reply: @escaping @Sendable () throws(CommandError) -> CommandResult) -> SafariBridge {
    SafariBridge(scriptURL: scriptURL, extractScriptURL: extractURL) { inv, t, cap throws(CommandError) in
        await rec.add(inv, t, cap)
        return try reply()
    }
}

struct SafariBridgeTests {
    @Test func listParsesUnicodeAndKeepsOnlyHttp() throws {
        let tabs = try SafariBridgeParser.parseTabs(try loadFixture("safari_list.json"))
        #expect(tabs.map(\.url.absoluteString) == ["https://example.com/a", "http://example.org/b?q=1"])
        #expect(tabs[0].title == "Café – Überblick 日本語")
        #expect(tabs[0].current && !tabs[1].current)
        #expect(tabs[1].window == 2)
    }

    @Test func emptyListAndMalformed() throws {
        #expect(try SafariBridgeParser.parseTabs(try loadFixture("safari_list_empty.json")).isEmpty)
        #expect(throws: SafariError.malformedOutput) { try SafariBridgeParser.parseTabs(Data("not json".utf8)) }
    }

    @Test(arguments: [
        ("safari_err_denied.txt", SafariError.automationDenied),
        ("safari_err_jsoff.txt", .javascriptFromAppleEventsOff),
        ("safari_err_notrunning.txt", .safariNotRunning),
        ("safari_err_tabchanged.txt", .tabChanged),
        ("safari_err_other.txt", .malformedOutput),
    ])
    func stderrMapsToCase(file: String, expected: SafariError) throws {
        #expect(SafariBridgeParser.classify(stderr: try loadFixture(file)) == expected)
    }

    @Test func tabsRunsOsascriptWithArgvOnly() async throws {
        let rec = Recorder()
        let data = try loadFixture("safari_list.json")
        let b = bridge(rec) { result(out: data) }
        let tabs = try await b.tabs()
        #expect(tabs.count == 2)
        let call = try #require(await rec.calls.first)
        #expect(call.executable.path == "/usr/bin/osascript")
        #expect(call.arguments == ["-l", "JavaScript", scriptURL.path, "list"])
        #expect(await rec.timeouts.first == .seconds(10))
        #expect(await rec.caps.first == SafariBridge.maxOutputBytes)
    }

    @Test func currentTabIsFlagged() async throws {
        let data = try loadFixture("safari_list.json")
        let b = bridge(Recorder()) { result(out: data) }
        #expect(try await b.currentTab()?.url.absoluteString == "https://example.com/a")
    }

    @Test func extractPassesTabIdentityNotUserText() async throws {
        let rec = Recorder()
        let page = """
        {"v":1,"title":"T","url":"https://example.com/a","text":"\(String(repeating: "x", count: 300))","headings":[],"links":[],"tables":[]}
        """
        let b = bridge(rec) { result(out: Data(page.utf8)) }
        let tab = SafariTab(window: 3, tab: 4, title: "'; do shell script \"rm -rf /\"", url: URL(string: "https://example.com/a")!, current: false)
        let got = try await b.extract(tab)
        #expect(got.title == "T")
        let call = try #require(await rec.calls.first)
        #expect(call.arguments == ["-l", "JavaScript", scriptURL.path, "extract", "3", "4", "https://example.com/a", extractURL.path])
        #expect(!call.arguments.joined().contains("rm -rf"))
        #expect(await rec.timeouts.first == .seconds(30))
    }

    @Test func extractRejectsPageWhoseLocationDiffersFromTab() async throws {
        let rec = Recorder()
        let page = """
        {"v":1,"title":"T","url":"https://evil.example.net/landing","text":"\(String(repeating: "x", count: 300))","headings":[],"links":[],"tables":[]}
        """
        let b = bridge(rec) { result(out: Data(page.utf8)) }
        let tab = SafariTab(window: 1, tab: 1, title: "t", url: URL(string: "https://example.com/a")!, current: false)
        await #expect(throws: SafariError.tabChanged) { try await b.extract(tab) }
    }

    @Test func extractAcceptsLocationThatNormalizesToTabURL() async throws {
        let rec = Recorder()
        let page = """
        {"v":1,"title":"T","url":"https://example.com/a?utm_source=x#top","text":"\(String(repeating: "x", count: 300))","headings":[],"links":[],"tables":[]}
        """
        let b = bridge(rec) { result(out: Data(page.utf8)) }
        let tab = SafariTab(window: 1, tab: 1, title: "t", url: URL(string: "https://example.com/a")!, current: false)
        #expect(try await b.extract(tab).url.absoluteString == "https://example.com/a")
    }

    @Test func nonZeroStatusMapsStderr() async throws {
        let err = try loadFixture("safari_err_denied.txt")
        let b = bridge(Recorder()) { result(1, err: err) }
        await #expect(throws: SafariError.automationDenied) { try await b.tabs() }
    }

    @Test func truncatedOutputIsTooLarge() async {
        let b = bridge(Recorder()) { result(out: Data("[]".utf8), truncated: true) }
        await #expect(throws: SafariError.outputTooLarge) { try await b.tabs() }
    }

    @Test func timeoutMaps() async {
        let b = bridge(Recorder()) { () throws(CommandError) -> CommandResult in throw CommandError.timedOut(after: .seconds(10)) }
        await #expect(throws: SafariError.timedOut) { try await b.tabs() }
    }

    @Test func malformedExtractOutput() async {
        let b = bridge(Recorder()) { result(out: Data("{}".utf8)) }
        let tab = SafariTab(window: 1, tab: 1, title: "", url: URL(string: "https://example.com/")!, current: true)
        await #expect(throws: SafariError.malformedOutput) { try await b.extract(tab) }
    }

    @Test func permissionStatusMapping() {
        #expect(SafariPermission.state(forStatus: 0) == .granted)
        #expect(SafariPermission.state(forStatus: -1743) == .denied)
        #expect(SafariPermission.state(forStatus: -1744) == .notDetermined)
        #expect(SafariPermission.state(forStatus: -600) == .safariNotRunning)
    }
}
