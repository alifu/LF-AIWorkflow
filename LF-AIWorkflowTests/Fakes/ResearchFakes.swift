//
//  ResearchFakes.swift
//  LF-AIWorkflowTests
//

import Foundation
import os
@testable import LF_AIWorkflow

struct FakeSafari: SafariControlling {
    let pages: [URL: CapturedPage]
    var failure: SafariError?

    func tabs() async throws(SafariError) -> [SafariTab] { [] }
    func currentTab() async throws(SafariError) -> SafariTab? { nil }
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage {
        if let failure { throw failure }
        guard let page = pages[tab.url] else { throw .tabChanged }
        return page
    }
    func permission() async -> SafariPermissionState { .granted }
}

struct FakeCrawler: ResearchCrawling {
    let pages: [CapturedPage]

    func crawl(start: [URL], limits: CrawlLimits) -> AsyncThrowingStream<CrawlEvent, Error> {
        AsyncThrowingStream { continuation in
            for page in pages { continuation.yield(.fetched(page, depth: 0)) }
            continuation.yield(.finished(CrawlSummary(fetched: pages.count, skipped: 0, stop: .completed)))
            continuation.finish()
        }
    }
}

/// Scripted research runner: a handler chooses the reply per request; every request is recorded.
final class FakeResearchRunner: ResearchClaudeRunning {
    enum Reply: Sendable {
        case outcome(StageRunOutcome)
        case hang
    }

    private struct State { var calls: [ResearchRunRequest] = []; var terminated = 0 }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let handler: @Sendable (ResearchRunRequest) -> Reply

    init(handler: @escaping @Sendable (ResearchRunRequest) -> Reply) { self.handler = handler }

    static func ok(_ text: String, session: String? = "22222222-2222-4222-8222-222222222222",
                   tokens: Int = 100, denials: [String] = []) -> Reply {
        .outcome(StageRunOutcome(
            text: text, sessionId: session,
            usage: TokenUsage(input: tokens, output: 0, cacheRead: 0, cacheCreation: 0),
            isError: false, permissionDenials: denials, exitStatus: 0))
    }

    static func error(_ text: String) -> Reply {
        .outcome(StageRunOutcome(text: text, sessionId: nil, usage: .zero, isError: true,
                                 permissionDenials: [], exitStatus: 1))
    }

    var calls: [ResearchRunRequest] { state.withLock { $0.calls } }
    var terminatedCount: Int { state.withLock { $0.terminated } }

    func run(_ request: ResearchRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        state.withLock { $0.calls.append(request) }
        let reply = handler(request)
        return AsyncThrowingStream { continuation in
            if case .outcome(let outcome) = reply {
                continuation.yield(.finished(outcome))
                continuation.finish()
            }
            continuation.onTermination = { [state] reason in
                if case .cancelled = reason { state.withLock { $0.terminated += 1 } }
            }
        }
    }
}
