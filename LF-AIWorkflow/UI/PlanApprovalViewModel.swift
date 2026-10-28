//
//  PlanApprovalViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

/// The two decisions on a plan; `WorkflowControlling` provides them.
@MainActor
protocol TaskDeciding: AnyObject {
    func approve(_ id: UUID) async
    func cancel(_ id: UUID) async
}

@MainActor @Observable
final class PlanApprovalViewModel {
    private let task: WorkflowTask
    private let loader: any PlanLoading
    private let opener: any EditorOpening
    private let decider: any TaskDeciding

    private(set) var document: PlanDocument?
    private(set) var loadError: String?
    private(set) var openError: String?
    private(set) var hasActed = false

    init(task: WorkflowTask, loader: any PlanLoading, opener: any EditorOpening, decider: any TaskDeciding) {
        self.task = task
        self.loader = loader
        self.opener = opener
        self.decider = decider
    }

    var title: String { task.title }
    var planPath: String? { task.planFile?.path }
    var canAct: Bool { !hasActed }

    /// Complexity: O(plan bytes) time, O(plan bytes) space
    func load() async {
        guard let file = task.planFile else {
            loadError = "No plan file was written for this task."
            return
        }
        do {
            document = try await loader.load(file)
            loadError = nil
        } catch {
            loadError = "Cannot read the plan at \(file.path)."
        }
    }

    /// Only the first decision counts; both buttons are disabled afterwards.
    func approve() async {
        guard canAct else { return }
        hasActed = true
        await decider.approve(task.id)
    }

    func cancelTask() async {
        guard canAct else { return }
        hasActed = true
        await decider.cancel(task.id)
    }

    func openInEditor() {
        guard let file = task.planFile else { return }
        let opened = opener.open(path: file.path, line: nil, within: task.workingDirectory)
        openError = opened ? nil : "Cannot open the plan: it is missing or outside the task folder."
    }
}
