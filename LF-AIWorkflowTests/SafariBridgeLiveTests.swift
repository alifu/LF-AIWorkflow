//
//  SafariBridgeLiveTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

enum SafariIntegration {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["LF_RUN_SAFARI_TESTS"] == "1" }
}

@Suite(.tags(.requiresSafari), .enabled(if: SafariIntegration.isEnabled), .serialized, .timeLimit(.minutes(2)))
struct SafariBridgeLiveTests {
    @Test func listsTabsAndExtractsCurrent() async throws {
        let bridge = try #require(SafariBridge.bundled())
        let tabs = try await bridge.tabs()
        #expect(!tabs.isEmpty)
        #expect(tabs.allSatisfy { ["http", "https"].contains($0.url.scheme) })
        if let current = try await bridge.currentTab() {
            #expect(current.url.absoluteString != "about:blank")
            let page = try await bridge.extract(current)
            #expect(!page.title.isEmpty || !page.text.isEmpty)
        }
    }
}
