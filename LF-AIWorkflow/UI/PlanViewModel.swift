//
//  PlanViewModel.swift
//  LF-AIWorkflow
//

import AppKit
import Foundation
import Observation

@MainActor
protocol Pasteboarding {
    func copy(_ string: String)
}

@MainActor
struct SystemPasteboard: Pasteboarding {
    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

enum PlanBadge: Sendable, Equatable {
    case approved, waiting

    var text: String { self == .approved ? "Approved" : "Waiting" }
    var accessibilityText: String { self == .approved ? "Approved" : "Waiting for approval" }
}

@MainActor @Observable
final class PlanViewModel {
    private let task: WorkflowTask
    private let loader: any PlanLoading
    private let opener: any EditorOpening
    private let pasteboard: any Pasteboarding

    private(set) var document: PlanDocument?
    private(set) var loadError: String?
    private(set) var openError: String?
    private(set) var didCopy = false

    init(task: WorkflowTask, loader: any PlanLoading, opener: any EditorOpening, pasteboard: any Pasteboarding) {
        self.task = task
        self.loader = loader
        self.opener = opener
        self.pasteboard = pasteboard
    }

    /// Research tasks and tasks started at Code have no plan file, so there is nothing to show.
    var isVisible: Bool { task.planFile != nil }
    var pathText: String { task.planFile?.path ?? "" }

    var badge: PlanBadge {
        let beforeApproval: Set<TaskState> = [.queued, .plan, .awaitingApproval]
        if beforeApproval.contains(task.state) { return .waiting }
        if task.state == .awaitingInput, let resume = task.resumeState, beforeApproval.contains(resume) { return .waiting }
        return .approved
    }

    /// Complexity: O(plan bytes) time, O(plan bytes) space
    func load() async {
        guard let file = task.planFile else { return }
        do {
            document = try await loader.load(file)
            loadError = nil
        } catch {
            document = nil
            loadError = "Cannot read the plan at \(file.path)."
        }
    }

    func openInEditor() {
        guard let file = task.planFile else { return }
        let opened = opener.open(path: file.path, line: nil, within: task.workingDirectory)
        openError = opened ? nil : "Cannot open the plan: it is missing or outside the task folder."
    }

    func copyPath() {
        guard let file = task.planFile else { return }
        pasteboard.copy(file.path)
        didCopy = true
    }
}
