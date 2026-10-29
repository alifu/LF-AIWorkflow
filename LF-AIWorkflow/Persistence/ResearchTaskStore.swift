//
//  ResearchTaskStore.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Persists research task metadata (TD-093). Never page content: only the question, state, paths and counters.
nonisolated protocol ResearchPersisting: Sendable {
    /// Stored tasks, oldest first; empty when there is no file, it is unreadable, or its version is unknown.
    func load() -> [ResearchTask]
    /// Replaces the stored set with `tasks` (given oldest first). Failures are logged, never thrown.
    func save(_ tasks: [ResearchTask])
}

/// One stored task. The sources preview is derived from page text, so it is dropped.
nonisolated struct ResearchRecord: Codable, Sendable, Equatable {
    let id: UUID
    let question: String
    let output: String
    let deep: Bool
    let state: String
    let needsBudgetInput: Bool
    let folderPath: String?
    let sessionId: String?
    let tokensUsed: Int
    let errorMessage: String?
    let denials: [String]
    let reportPath: String?

    /// Complexity: O(1) time, O(1) space
    init(_ task: ResearchTask) {
        id = task.id; question = task.question; output = task.output.rawValue; deep = task.deep
        state = task.state.rawValue; needsBudgetInput = task.inputReason == .budgetExceeded
        folderPath = task.folder?.url.path; sessionId = task.sessionId; tokensUsed = task.tokensUsed
        errorMessage = task.errorMessage; denials = task.denials; reportPath = task.reportFile?.path
    }

    /// Nil when the stored output or state is not a known value.
    /// Complexity: O(1) time, O(1) space
    var task: ResearchTask? {
        guard let output = OutputKind(rawValue: output), let state = ResearchState(rawValue: state) else { return nil }
        return ResearchTask(
            id: id, question: question, output: output, deep: deep, state: state,
            inputReason: needsBudgetInput ? .budgetExceeded : nil,
            folder: folderPath.map { ResearchFolder(url: URL(fileURLWithPath: $0, isDirectory: true)) },
            sessionId: sessionId, tokensUsed: tokensUsed, errorMessage: errorMessage, denials: denials,
            reportFile: reportPath.map { URL(fileURLWithPath: $0) })
    }
}

/// Versioned envelope: bump `currentVersion` and branch in `load` when the record shape changes.
nonisolated struct ResearchFile: Codable, Sendable {
    static let currentVersion = 1
    let version: Int
    let tasks: [ResearchRecord]
}

/// Research tasks as JSON in one file (default next to `tasks.json`). Keeps every live task plus the newest
/// `maxFinished` finished ones.
nonisolated struct ResearchTaskStore: ResearchPersisting {
    static let maxFinished = 100

    let fileURL: URL

    /// Complexity: O(1) time, O(1) space
    init(fileURL: URL) { self.fileURL = fileURL }

    /// Complexity: O(n) time, O(n) space (n = stored tasks)
    func load() -> [ResearchTask] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let file = try JSONDecoder.epochMillis.decode(ResearchFile.self, from: data)
            guard file.version == ResearchFile.currentVersion else {
                AppLog.workflow.warning("ignoring research file with unknown version \(file.version)")
                FileBackup.preserve(fileURL)
                return []
            }
            let tasks = file.tasks.compactMap(\.task)
            if tasks.count != file.tasks.count {
                AppLog.workflow.warning("dropped \(file.tasks.count - tasks.count) research records with unknown values")
                FileBackup.preserve(fileURL, keepOriginal: true)
            }
            return tasks
        } catch {
            AppLog.workflow.warning("cannot read the research file: \(error.localizedDescription)")
            FileBackup.preserve(fileURL)
            return []
        }
    }

    /// Complexity: O(n) time, O(n) space (n = tasks)
    func save(_ tasks: [ResearchTask]) {
        let finishedIds = Set(tasks.filter { $0.state.isFinished }.suffix(Self.maxFinished).map(\.id))
        let kept = tasks.filter { !$0.state.isFinished || finishedIds.contains($0.id) }
        let file = ResearchFile(version: ResearchFile.currentVersion, tasks: kept.map(ResearchRecord.init))
        do {
            let encoder = JSONEncoder.epochMillis
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.workflow.warning("cannot save the research file: \(error.localizedDescription)")
        }
    }
}

/// Launch-time fix-up: a task that was mid-run has lost its in-memory pages, so it comes back failed.
nonisolated enum ResearchRestore {
    static let interruptedMessage = "Interrupted by relaunch. Submit the question again."

    /// Complexity: O(n) time, O(n) space
    static func apply(_ tasks: [ResearchTask]) -> [ResearchTask] {
        tasks.map { task in
            task.state.isFinished ? task : task.with(state: .failed).with(inputReason: nil).with(errorMessage: interruptedMessage)
        }
    }
}

extension ResearchState {
    /// Done, failed or cancelled.
    nonisolated var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
}
