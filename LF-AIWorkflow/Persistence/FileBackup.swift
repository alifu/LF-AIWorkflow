//
//  FileBackup.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Keeps an unreadable store file as `<name>.bak-<unix time>` so the next save cannot destroy it (HIGH-1).
nonisolated enum FileBackup {
    static let maxBackups = 3

    /// Moves (or copies, when `keepOriginal`) `url` aside, then prunes to the newest `maxBackups`. Best effort: failures are logged.
    /// Complexity: O(b log b) time, O(b) space (b = backups in the folder, at most a few) plus the file copy
    static func preserve(_ url: URL, keepOriginal: Bool = false, now: Date = Date()) {
        let fileManager = FileManager.default
        let stamp = Int(now.timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bak-\(stamp)")
        do {
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            if keepOriginal { try fileManager.copyItem(at: url, to: backup) } else { try fileManager.moveItem(at: url, to: backup) }
        } catch {
            AppLog.workflow.warning("cannot back up \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }
        prune(url)
    }

    /// Backups of `url`, oldest first.
    /// Complexity: O(b log b) time, O(b) space
    static func backups(of url: URL) -> [URL] {
        let prefix = url.lastPathComponent + ".bak-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.compactMap { name -> (Int, URL)? in
            guard name.hasPrefix(prefix), let stamp = Int(name.dropFirst(prefix.count)) else { return nil }
            return (stamp, url.deletingLastPathComponent().appendingPathComponent(name))
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func prune(_ url: URL) {
        for old in backups(of: url).dropLast(maxBackups) {
            do { try FileManager.default.removeItem(at: old) } catch {
                AppLog.workflow.warning("cannot remove old backup \(old.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
