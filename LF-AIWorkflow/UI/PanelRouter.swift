//
//  PanelRouter.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

enum ExpandedTab: String, CaseIterable, Sendable, Identifiable {
    case tasks, new, terminal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .new: "New"
        case .terminal: "Terminal"
        }
    }
}

/// What the New tab composes.
enum ComposerMode: String, CaseIterable, Sendable, Identifiable {
    case code, research

    var id: String { rawValue }
    var title: String { self == .code ? "Code" : "Research" }
}

/// Which tab and which task detail the expanded panel shows.
@MainActor @Observable
final class PanelRouter {
    var tab: ExpandedTab = .tasks
    var detailTaskID: UUID?
    /// Lives here so the draft survives tab switches and the panel collapsing.
    let composer: ComposerViewModel
    var composerMode: ComposerMode = .code
    /// Nil until research is wired in; the New tab then shows only the Code composer.
    let research: ResearchViewModel?
    let researchComposer: ResearchComposerViewModel?

    init(composer: ComposerViewModel = ComposerViewModel(bookmarks: BookmarkStore(), picker: OpenPanelPicker(),
                                                          inspector: FileAttachmentInspector()),
         research: ResearchViewModel? = nil, researchComposer: ResearchComposerViewModel? = nil) {
        self.composer = composer
        self.research = research
        self.researchComposer = researchComposer
    }

    func show(task id: UUID) {
        tab = .tasks
        detailTaskID = id
    }

    func closeDetail() { detailTaskID = nil }
}
