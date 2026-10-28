//
//  ResearchTask.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum ResearchInputReason: Sendable, Equatable { case budgetExceeded }

/// What the user asked for. Sources come from Safari tabs, typed URLs (crawled) and the research inbox.
nonisolated struct ResearchDraft: Sendable {
    let question: String
    let output: OutputKind
    let deep: Bool
    var urls: [URL] = []
    var tabs: [SafariTab] = []
    var inboxPages: [CapturedPage] = []
    var limits = CrawlLimits()
}

/// Immutable research task snapshot; every change returns a copy.
nonisolated struct ResearchTask: Sendable, Equatable, Identifiable {
    let id: UUID
    let question: String
    let output: OutputKind
    let deep: Bool
    let state: ResearchState
    let inputReason: ResearchInputReason?
    let folder: ResearchFolder?
    let sessionId: String?
    let preview: SourcesPreview?
    let tokensUsed: Int
    let errorMessage: String?
    let denials: [String]
    let reportFile: URL?

    init(id: UUID = UUID(), question: String, output: OutputKind, deep: Bool, state: ResearchState = .queued,
         inputReason: ResearchInputReason? = nil, folder: ResearchFolder? = nil, sessionId: String? = nil,
         preview: SourcesPreview? = nil, tokensUsed: Int = 0, errorMessage: String? = nil, denials: [String] = [],
         reportFile: URL? = nil) {
        self.id = id; self.question = question; self.output = output; self.deep = deep; self.state = state
        self.inputReason = inputReason; self.folder = folder; self.sessionId = sessionId; self.preview = preview
        self.tokensUsed = tokensUsed; self.errorMessage = errorMessage; self.denials = denials
        self.reportFile = reportFile
    }

    func with(state: ResearchState) -> ResearchTask { copy(state: state) }
    func with(inputReason: ResearchInputReason?) -> ResearchTask { copy(inputReason: .some(inputReason)) }
    func with(folder: ResearchFolder?) -> ResearchTask { copy(folder: .some(folder)) }
    func with(sessionId: String?) -> ResearchTask { copy(sessionId: .some(sessionId)) }
    func with(preview: SourcesPreview?) -> ResearchTask { copy(preview: .some(preview)) }
    func with(tokensUsed: Int) -> ResearchTask { copy(tokensUsed: tokensUsed) }
    func with(errorMessage: String?) -> ResearchTask { copy(errorMessage: .some(errorMessage)) }
    func with(denials: [String]) -> ResearchTask { copy(denials: denials) }
    func with(reportFile: URL?) -> ResearchTask { copy(reportFile: .some(reportFile)) }

    private func copy(state: ResearchState? = nil, inputReason: ResearchInputReason?? = nil,
                      folder: ResearchFolder?? = nil, sessionId: String?? = nil, preview: SourcesPreview?? = nil,
                      tokensUsed: Int? = nil, errorMessage: String?? = nil, denials: [String]? = nil,
                      reportFile: URL?? = nil) -> ResearchTask {
        ResearchTask(
            id: id, question: question, output: output, deep: deep, state: state ?? self.state,
            inputReason: inputReason ?? self.inputReason, folder: folder ?? self.folder,
            sessionId: sessionId ?? self.sessionId, preview: preview ?? self.preview,
            tokensUsed: tokensUsed ?? self.tokensUsed, errorMessage: errorMessage ?? self.errorMessage,
            denials: denials ?? self.denials, reportFile: reportFile ?? self.reportFile)
    }
}
