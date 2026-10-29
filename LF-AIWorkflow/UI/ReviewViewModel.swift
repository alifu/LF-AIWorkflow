//
//  ReviewViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

@MainActor @Observable
final class ReviewViewModel {
    private let task: WorkflowTask
    private let loader: any ReviewLoading
    private let opener: any EditorOpening
    private let sendToFix: @MainActor ([Finding]) -> Void

    private(set) var findings: [Finding] = []
    private(set) var unparsedCount = 0
    private(set) var message: String?
    private(set) var isLoaded = false

    init(task: WorkflowTask, loader: any ReviewLoading, opener: any EditorOpening,
         sendToFix: @escaping @MainActor ([Finding]) -> Void = { _ in }) {
        self.sendToFix = sendToFix
        self.task = task
        self.loader = loader
        self.opener = opener
    }

    var countsBySeverity: [Severity: Int] { Dictionary(findings.map { ($0.severity, 1) }, uniquingKeysWith: +) }
    var reportPath: String? { task.reviewFile?.path }
    var title: String { task.title }
    static let sendHighToFixNote = "Runs one more Fix stage with the CRITICAL and HIGH findings, then tests and review again."
    /// CRITICAL and HIGH findings, the ones "Send HIGH to Fix" hands to the engine.
    var highFindings: [Finding] { findings.filter { $0.severity <= .high } }
    var canSendHighToFix: Bool { task.state == .done && !highFindings.isEmpty }

    /// Complexity: O(f) time, O(f) space
    func sendHighToFix() {
        guard canSendHighToFix else { return }
        sendToFix(highFindings)
    }

    /// Complexity: O(f log f) time, O(f) space
    func load() async {
        guard let file = task.reviewFile else {
            message = "No review report was saved for this task."
            return
        }
        do {
            let report = try await loader.load(file)
            findings = ReviewReport.ordered(report.findings)
            unparsedCount = report.unparsedLineCount
            message = nil
            isLoaded = true
        } catch {
            message = "Cannot read the review report at \(file.path)."
        }
    }

    /// Opens `file:line` only if it resolves inside the task's working directory.
    /// Complexity: O(len) time, O(len) space
    func open(_ finding: Finding) {
        let opened = opener.open(path: finding.file, line: finding.line, within: task.workingDirectory)
        message = opened ? nil : "Cannot open \(finding.file): it is missing or outside the task folder."
    }

    func openWorktree() { opener.reveal(task.workingDirectory) }
}
