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
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The entry point's path when its content differs from `baseline`; nil when unchanged, unguarded or unbaselined.
    /// Complexity: O(file bytes) time, O(file bytes) space
    static func modifiedEntryPoint(of command: TestCommand, in dir: URL, since baseline: String?) -> String? {
        guard let entry = command.entryPoint, let baseline,
              let now = fingerprint(of: command, in: dir), now != baseline else { return nil }
        return entry
    }
}
