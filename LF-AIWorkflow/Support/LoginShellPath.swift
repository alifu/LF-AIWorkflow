//
//  LoginShellPath.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Resolves `$PATH` as the user's login shell sees it (GUI apps get a minimal PATH). Runs once, then caches.
actor LoginShellPath {
    private static let marker = "__LFPATH__"
    private let shell: String
    private let timeout: Duration
    private var task: Task<String?, Never>?

    init(shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh", timeout: Duration = .seconds(5)) {
        self.shell = shell
        self.timeout = timeout
    }

    /// Nil on spawn failure, timeout, or non-zero exit.
    func resolve() async -> String? {
        if let task { return await task.value }
        let shell = shell, timeout = timeout
        let created = Task { await Self.run(shell: shell, timeout: timeout) }
        task = created
        return await created.value
    }

    /// Runs through `CommandRunner`: pipes drain concurrently, a timeout sends SIGTERM then SIGKILL to the
    /// shell's group, and the call returns once it is reaped (TD-107).
    /// Complexity: O(n) time, O(n) space (n = shell output size)
    private static func run(shell: String, timeout: Duration) async -> String? {
        let inv = ProcessInvocation(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-lc", "printf \"\(marker)%s\(marker)\" \"$PATH\""],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: FileManager.default.temporaryDirectory,
            stdin: Data())
        do {
            let result = try await CommandRunner.run(inv, timeout: timeout, maxOutputBytes: 1 << 20)
            guard result.status == 0 else {
                AppLog.claude.error("login shell exited with status \(result.status)")
                return nil
            }
            return parse(String(decoding: result.stdout, as: UTF8.self))
        } catch {
            AppLog.claude.error("login shell PATH lookup failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Extracts the text between the markers; profile scripts may print noise around them.
    /// Complexity: O(n) time, O(n) space
    static func parse(_ output: String) -> String? {
        guard let start = output.range(of: marker),
              let end = output.range(of: marker, range: start.upperBound..<output.endIndex) else { return nil }
        let value = String(output[start.upperBound..<end.lowerBound])
        return value.isEmpty ? nil : value
    }
}
