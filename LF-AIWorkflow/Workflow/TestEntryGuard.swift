//
//  TestEntryGuard.swift
//  LF-AIWorkflow
//

import Foundation
import CryptoKit

/// Detects edits to the auto-detected test entry point (e.g. `Makefile`, `scripts/check.sh`) made while the Code and
/// Fix stages ran. Running a file the model just wrote, with the user's environment, needs the user's say-so.
nonisolated enum TestEntryGuard {
    private static let missing = "missing"

    /// SHA-256 of the entry point's bytes, `"missing"` if absent; nil when the command has no entry point.
    /// Complexity: O(file bytes) time, O(file bytes) space
    static func fingerprint(of command: TestCommand, in dir: URL) -> String? {
        guard let entry = command.entryPoint else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(entry)) else { return missing }
        var hasher = SHA256()
        hasher.update(data: data)
        for extra in companions(of: entry, in: dir) {
            hasher.update(data: Data(extra.lastPathComponent.utf8))
            hasher.update(data: (try? Data(contentsOf: extra)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// TD-102: for an Xcode project, the shared schemes (they pick the test plan and pre/post actions) count too.
    private static func companions(of entry: String, in dir: URL) -> [URL] {
        guard entry.hasSuffix(".xcodeproj/project.pbxproj") || entry.hasSuffix(".xcworkspace/project.pbxproj") else { return [] }
        let container = dir.appendingPathComponent(entry).deletingLastPathComponent()
        let schemes = container.appendingPathComponent("xcshareddata/xcschemes")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: schemes.path)) ?? []).sorted()
        return names.map { schemes.appendingPathComponent($0) }
    }

    /// TD-102: the project file a user-supplied override command runs or sources (`./run.sh`, `scripts/t.sh`),
    /// first match wins. Words that leave the project (`..`, absolute paths) are not guarded.
    /// Complexity: O(w) time, O(w) space (w = words in the command)
    static func entryPoint(forOverride command: String, in dir: URL) -> String? {
        for raw in command.split(whereSeparator: { " \t\n;&|()<>".contains($0) }) {
            var word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if word.hasPrefix("./") { word.removeFirst(2) }
            guard !word.isEmpty, !word.hasPrefix("/"), !word.hasPrefix("-"), !word.contains("..") else { continue }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(word).path, isDirectory: &isDir), !isDir.boolValue {
                return word
            }
        }
        return nil
    }

    /// The entry point's path when its content differs from `baseline`; nil when unchanged, unguarded or unbaselined.
    /// Complexity: O(file bytes) time, O(file bytes) space
    static func modifiedEntryPoint(of command: TestCommand, in dir: URL, since baseline: String?) -> String? {
        guard let entry = command.entryPoint, let baseline,
              let now = fingerprint(of: command, in: dir), now != baseline else { return nil }
        return entry
    }
}
