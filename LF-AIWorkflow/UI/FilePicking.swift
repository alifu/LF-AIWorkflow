//
//  FilePicking.swift
//  LF-AIWorkflow
//

import AppKit

nonisolated enum PickRequest: Sendable, Equatable {
    case documents, skillFolder, project
}

/// Seam over `NSOpenPanel` so the composer is testable.
@MainActor
protocol FilePicking {
    func pick(_ request: PickRequest) async -> [URL]
}

@MainActor
struct OpenPanelPicker: FilePicking {
    func pick(_ request: PickRequest) async -> [URL] {
        let panel = NSOpenPanel()
        switch request {
        case .documents:
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true; panel.prompt = "Attach"
            panel.message = "Choose documents to attach as paths"
        case .skillFolder:
            panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true; panel.prompt = "Add"
            panel.message = "Choose skill folders"
        case .project:
            panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false; panel.prompt = "Choose"
            panel.message = "Choose the project folder"
        }
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.urls : []) }
        }
    }
}
