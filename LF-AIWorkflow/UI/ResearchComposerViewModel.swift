//
//  ResearchComposerViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

/// Why the draft cannot run yet.
nonisolated enum ResearchDraftIssue: Sendable, Equatable {
    case emptyQuestion, noSources

    var message: String {
        switch self {
        case .emptyQuestion: "Type a question first."
        case .noSources: "Tick a tab, add a URL or use the inbox."
        }
    }
}

/// One Safari tab in the picker; `selected` survives list refreshes (matched by URL).
nonisolated struct TabChoice: Sendable, Equatable, Identifiable {
    let tab: SafariTab
    var selected: Bool
    var id: String { "\(tab.window)-\(tab.tab)-\(tab.url.absoluteString)" }
}

/// Draft state of the Research composer. Sources: Safari tabs (ticked), typed URLs (crawled), inbox pages.
@MainActor @Observable
final class ResearchComposerViewModel {
    var question = ""
    var urlInput = ""
    var output: OutputKind = .summary
    var deep = false
    private(set) var urls: [URL] = []
    private(set) var urlError: String?
    private(set) var tabs: [TabChoice] = []
    private(set) var inboxPages: [CapturedPage] = []
    private(set) var depth = 0
    private(set) var maxPages = CrawlLimits.defaultMaxPages
    private(set) var safariError: SafariError?
    private(set) var isSubmitting = false

    @ObservationIgnored private let safari: any SafariControlling
    @ObservationIgnored private let research: ResearchViewModel
    @ObservationIgnored private var selectedTabURLs: Set<URL> = []
    @ObservationIgnored private var hasLoadedTabs = false

    init(safari: any SafariControlling, research: ResearchViewModel) {
        self.safari = safari
        self.research = research
    }

    var setupGuide: SafariSetupGuide? { SafariSetupGuide.make(state: research.safariState, error: safariError) }
    var estimatedTokens: Int? { research.estimatedTokens }
    var inboxCount: Int { research.inboxCount }
    var selectedTabs: [SafariTab] { tabs.filter(\.selected).map(\.tab) }

    var issue: ResearchDraftIssue? {
        if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyQuestion }
        if selectedTabs.isEmpty && urls.isEmpty && inboxPages.isEmpty { return .noSources }
        return nil
    }

    // MARK: - Limits

    func setDepth(_ value: Int) { depth = min(max(value, 0), CrawlLimits.maxDepthCap) }
    func setMaxPages(_ value: Int) { maxPages = min(max(value, 1), CrawlLimits.maxPagesCap) }

    // MARK: - Sources

    /// Reads permission and tabs. The current tab is the only one ticked, and only on the first load;
    /// later refreshes keep the user's ticks by URL.
    /// Complexity: O(t) time, O(t) space for t tabs
    func refreshTabs() async {
        research.setSafariState(await safari.permission())
        do {
            let list = try await safari.tabs()
            safariError = nil
            if !hasLoadedTabs {
                selectedTabURLs = Set(list.filter(\.current).map(\.url))
                hasLoadedTabs = true
            }
            tabs = list.map { TabChoice(tab: $0, selected: selectedTabURLs.contains($0.url)) }
        } catch {
            safariError = error
            tabs = []
        }
    }

    func toggle(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].selected.toggle()
        let url = tabs[index].tab.url
        if tabs[index].selected { selectedTabURLs.insert(url) } else { selectedTabURLs.remove(url) }
    }

    /// Validates `urlInput` (canonical form, then the SSRF host policy); shows an inline error on failure.
    func addURL() {
        switch research.addURL(urlInput) {
        case .success(let url):
            if !urls.contains(url) { urls.append(url) }
            urlInput = ""
            urlError = nil
        case .failure(.invalid):
            urlError = "Enter a full http or https address."
        case .failure(.blocked):
            urlError = "That address is not allowed (local or private network)."
        }
    }

    func removeURL(_ url: URL) { urls.removeAll { $0 == url } }

    func useInbox() async { inboxPages = await research.useInbox() }

    func clearInbox() { inboxPages = [] }

    // MARK: - Submit

    /// The draft to submit, or nil while `issue` is set.
    func draft() -> ResearchDraft? {
        guard issue == nil else { return nil }
        var limits = CrawlLimits()
        limits.depth = depth
        limits.maxPages = maxPages
        return ResearchDraft(question: question.trimmingCharacters(in: .whitespacesAndNewlines), output: output,
                             deep: deep, urls: urls, tabs: selectedTabs, inboxPages: inboxPages,
                             limits: limits.clamped())
    }

    /// Preview stops at the sources preview; Run also sends when nothing is flagged. Clears the draft afterwards.
    func submit(run: Bool) async {
        guard !isSubmitting, let draft = draft() else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        guard await research.preview(draft, autoSend: run) != nil else { return }
        question = ""
        urls = []
        inboxPages = []
    }
}
