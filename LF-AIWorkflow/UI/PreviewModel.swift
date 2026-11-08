//
//  PreviewModel.swift
//  LF-AIWorkflow
//

#if DEBUG
import Foundation
import Observation

/// Engine-free model for `#Preview`s.
@MainActor @Observable
final class PreviewModel: WorkflowControlling {
    var rows: [TaskRowModel]
    var tasks: [WorkflowTask]
    var summary: CollapsedSummary
    var todayTokens = 14_600
    var peek: PeekMessage?
    var lastError: String?
    var logRevision = 0

    init(rows: [TaskRowModel]? = nil) {
        let source = PreviewFixtures.sampleTasks
        tasks = source
        let built = rows ?? source.map { TaskRowModel($0, now: PreviewFixtures.epoch.addingTimeInterval(187)) }
        self.rows = built
        summary = CollapsedSummary(activeCount: built.filter(\.isRunning).count, leadStep: .fix,
                                   attentionCount: built.filter(\.needsAttention).count)
    }

    func submit(_ draft: TaskDraft) async {}
    func approve(_ id: UUID) async -> Bool { true }
    func cancel(_ id: UUID) async {}
    func resume(_ id: UUID, raising tokens: Int) async {}
    func skipTests(_ id: UUID) async {}
    func retry(_ id: UUID) async {}
    func sendToFix(_ id: UUID, findings: [Finding]) async {}
    func removeWorktree(_ id: UUID) async {}
    func clearDone() {}
    func clearError() { lastError = nil }
    func openWorktree(_ id: UUID) {}
    func task(_ id: UUID) -> WorkflowTask? { tasks.first { $0.id == id } }
    func log(for id: UUID) async -> [TaskLogLine] {
        (0..<6).map { TaskLogLine(id: $0, stage: .code, text: "Editing Sources/File\($0).swift") }
    }
}
#endif
