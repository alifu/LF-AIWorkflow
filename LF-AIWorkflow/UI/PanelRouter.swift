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

/// Which tab and which task detail the expanded panel shows.
@MainActor @Observable
final class PanelRouter {
    var tab: ExpandedTab = .tasks
    var detailTaskID: UUID?
    /// Lives here so the draft survives tab switches and the panel collapsing.
    let composer: ComposerViewModel

    init(composer: ComposerViewModel = ComposerViewModel(bookmarks: BookmarkStore(), picker: OpenPanelPicker(),
                                                          inspector: FileAttachmentInspector())) {
        self.composer = composer
    }

    func show(task id: UUID) {
        tab = .tasks
        detailTaskID = id
    }

    func closeDetail() { detailTaskID = nil }
}
