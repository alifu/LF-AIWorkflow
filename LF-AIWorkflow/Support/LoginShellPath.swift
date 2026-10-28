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

    /// Complexity: O(n) time, O(n) space (n = shell output size)
    private static func run(shell: String, timeout: Duration) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "printf \"\(marker)%s\(marker)\" \"$PATH\""]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let readFD = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)

        let status: Int32? = await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try SpawnGate.withLock { try process.run() }
            } catch {
                AppLog.claude.error("login shell spawn failed: \(error.localizedDescription, privacy: .public)")
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning {
                    AppLog.claude.error("login shell PATH lookup timed out")
                    process.terminate()
                }
            }
        }
        guard status == 0 else {
            if let status { AppLog.claude.error("login shell exited with status \(status)") }
            return nil
        }
        // The shell has exited, so everything it wrote is already in the pipe.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(readFD, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) } else { break }
        }
        return parse(String(decoding: data, as: UTF8.self))
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
