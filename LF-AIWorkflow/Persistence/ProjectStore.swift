//
//  ProjectStore.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Persists the engine's tasks. Called from the engine actor, so implementations may do blocking file I/O.
/// Later stores (research tasks, TD-093) can reuse `JSONFileStore`.
nonisolated protocol TaskPersisting: Sendable {
    /// Every stored task; empty when there is no file, it is unreadable, or its version is unknown.
    func load() -> [WorkflowTask]
    /// Replaces the stored set with `tasks` (atomic write). Failures are logged, never thrown.
    func save(_ tasks: [WorkflowTask])
}

/// Versioned JSON envelope: bump `currentVersion` and branch in `load` when the task shape changes.
nonisolated struct TaskFile: Codable, Sendable {
    static let currentVersion = 1
    let version: Int
    let tasks: [WorkflowTask]
}

/// Tasks as JSON in one file (default `~/Library/Application Support/LF-AIWorkflow/tasks.json`).
/// Keeps every live task plus the newest `maxFinished` finished ones, so the file stays bounded.
nonisolated struct ProjectStore: TaskPersisting {
    static let maxFinished = 200

    let fileURL: URL

    /// Complexity: O(1) time, O(1) space
    init(fileURL: URL) { self.fileURL = fileURL }

    /// Complexity: O(n) time, O(n) space (n = stored tasks)
    func load() -> [WorkflowTask] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let file = try JSONDecoder.epochMillis.decode(TaskFile.self, from: data)
            guard file.version == TaskFile.currentVersion else {
                AppLog.workflow.warning("ignoring tasks file with unknown version \(file.version)")
                FileBackup.preserve(fileURL)
                return []
            }
            return file.tasks
        } catch {
            AppLog.workflow.warning("cannot read the tasks file: \(error.localizedDescription)")
            FileBackup.preserve(fileURL)
            return []
        }
    }

    /// Complexity: O(n log n) time, O(n) space (n = tasks)
    func save(_ tasks: [WorkflowTask]) {
        let live = tasks.filter { !$0.state.isTerminal }
        let finished = tasks.filter { $0.state.isTerminal }.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maxFinished)
        let file = TaskFile(version: TaskFile.currentVersion, tasks: (live + finished).sorted { $0.createdAt < $1.createdAt })
        do {
            let encoder = JSONEncoder.epochMillis
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.workflow.warning("cannot save the tasks file: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    nonisolated static var epochMillis: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var epochMillis: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
