//
//  ToolVersionProbe.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum ToolProbeError: Error, Sendable, Equatable {
    case exited(Int32)
    case timedOut
    case spawnFailed
    case noOutput

    var message: String {
        switch self {
        case .exited(let status): "The tool exited with status \(status)."
        case .timedOut: "The tool did not answer in time."
        case .spawnFailed: "The tool could not be started."
        case .noOutput: "The tool printed no version."
        }
    }
}

/// Runs `<tool> --version` through `CommandRunner` (argv only, no shell) and returns the first output line.
nonisolated enum ToolVersionProbe {
    static let timeout: Duration = .seconds(5)

    /// Complexity: O(n) time in output bytes, O(n) space
    static func run(_ executable: URL) async -> Result<String, ToolProbeError> {
        let invocation = ProcessInvocation(
            executable: executable, arguments: ["--version"], environment: ProcessInfo.processInfo.environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser, stdin: Data())
        do {
            let result = try await CommandRunner.run(invocation, timeout: timeout)
            guard result.status == 0 else { return .failure(.exited(result.status)) }
            guard let line = versionLine(from: result.stdout) else { return .failure(.noOutput) }
            return .success(line)
        } catch CommandError.timedOut {
            return .failure(.timedOut)
        } catch {
            return .failure(.spawnFailed)
        }
    }

    /// The first non-empty line, trimmed.
    /// Complexity: O(n) time, O(n) space (n = bytes)
    static func versionLine(from stdout: Data) -> String? {
        String(decoding: stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
