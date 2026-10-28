//
//  TestRunner.swift
//  LF-AIWorkflow
//

import Foundation
import os
import LFCore

/// Detects a project's test command and runs it under a pty (so tools line-buffer like in a terminal).
/// Output is kept in a ring buffer (newest `maxLogBytes`); only the error excerpt leaves this type.
actor TestRunner: TestRunning {
    private static let killGraceMs: Int32 = 2000
    private static let envPath = URL(fileURLWithPath: "/usr/bin/env")
    private static let shellPath = URL(fileURLWithPath: "/bin/sh")

    private let override: String?
    private let timeout: Duration
    private let errorMaxTokens: Int
    private let maxLogBytes: Int
    private let environment: [String: String]

    init(override: String? = nil, timeout: Duration = .seconds(600), errorMaxTokens: Int = 1_500,
         maxLogBytes: Int = 32 << 20, environment: [String: String]) {
        self.override = override.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.timeout = timeout
        self.errorMaxTokens = errorMaxTokens
        self.maxLogBytes = maxLogBytes
        self.environment = environment
    }

    // MARK: - Detection

    /// Plan §3 order: `scripts/check.sh`, `gradlew`, `*.xcworkspace`, `*.xcodeproj`, `Package.swift`, `package.json`,
    /// `Cargo.toml`, `go.mod`, `Makefile`. Tools run through `/usr/bin/env` so the run environment's PATH resolves them.
    /// Complexity: O(e) time, O(e) space (e = entries in `root`)
    static func detect(in root: URL, fileManager: FileManager = .default) -> TestCommand? {
        if let script = checkScript(root, fileManager) { return script }
        let names = ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        if names.contains("gradlew") { return gradle(root, fileManager) }
        if let container = names.first(where: { $0.hasSuffix(".xcworkspace") }) ?? names.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let url = root.appendingPathComponent(container)
            return try? xcodebuildCommand(container: url, scheme: scheme(for: url, fileManager), onlyTesting: [])
        }
        let simple: [(file: String, tool: [String])] = [
            ("Package.swift", ["swift", "test"]), ("package.json", ["npm", "test"]), ("Cargo.toml", ["cargo", "test"]),
            ("go.mod", ["go", "test", "./..."]), ("Makefile", ["make", "test"]),
        ]
        guard let match = simple.first(where: { names.contains($0.file) }) else { return nil }
        return tool(match.tool)
    }

    /// TD-023: one `-only-testing:<target>` argument per target; commas anywhere throw (the CLI would split a
    /// tool rule at them). `container` is referenced by file name: the command runs inside the working directory.
    /// Complexity: O(t) time, O(t) space (t = targets)
    static func xcodebuildCommand(container: URL, scheme: String, onlyTesting: [String]) throws(WorkflowError) -> TestCommand {
        let flag = container.pathExtension == "xcworkspace" ? "-workspace" : "-project"
        let words = ["xcodebuild", "test", flag, container.lastPathComponent, "-scheme", scheme,
                     "-destination", "platform=macOS"] + onlyTesting.map { "-only-testing:\($0)" }
        if let bad = words.first(where: { $0.contains(",") }) {
            throw .invalidTestTarget(bad.hasPrefix("-only-testing:") ? String(bad.dropFirst("-only-testing:".count)) : bad)
        }
        return tool(words)
    }

    func detect(in root: URL) async -> TestCommand? {
        if let override {
            return TestCommand(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", override], display: override)
        }
        return Self.detect(in: root)
    }

    private static func tool(_ words: [String]) -> TestCommand {
        TestCommand(executable: envPath, arguments: words, display: words.map(quoted).joined(separator: " "))
    }

    private static func quoted(_ word: String) -> String {
        word.contains(where: { $0 == " " || $0 == "'" }) ? "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'" : word
    }

    private static func checkScript(_ root: URL, _ fm: FileManager) -> TestCommand? {
        let script = root.appendingPathComponent("scripts/check.sh")
        guard fm.fileExists(atPath: script.path) else { return nil }
        if fm.isExecutableFile(atPath: script.path) {
            return TestCommand(executable: script, arguments: [], display: "scripts/check.sh")
        }
        return TestCommand(executable: shellPath, arguments: ["scripts/check.sh"], display: "scripts/check.sh")
    }

    private static func gradle(_ root: URL, _ fm: FileManager) -> TestCommand {
        let wrapper = root.appendingPathComponent("gradlew")
        if fm.isExecutableFile(atPath: wrapper.path) {
            return TestCommand(executable: wrapper, arguments: ["check"], display: "./gradlew check")
        }
        return TestCommand(executable: shellPath, arguments: ["gradlew", "check"], display: "./gradlew check")
    }

    /// First shared scheme (sorted) of the container, else the container's name.
    private static func scheme(for container: URL, _ fm: FileManager) -> String {
        let dir = container.appendingPathComponent("xcshareddata/xcschemes").path
        let schemes = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".xcscheme") }.sorted()
        return schemes.first.map { ($0 as NSString).deletingPathExtension } ?? container.deletingPathExtension().lastPathComponent
    }

    // MARK: - Running

    /// Runs `cmd` in `dir` under a pty with empty stdin. Timeout: SIGTERM to the process group, SIGKILL after 2 s.
    /// Complexity: O(n) time in output bytes, O(maxLogBytes) space
    func run(_ cmd: TestCommand, in dir: URL) async -> TestOutcome {
        guard FileManager.default.isExecutableFile(atPath: cmd.executable.path) else { return .notFound }
        let log: RingBuffer
        let process: PTYProcess
        do {
            log = try RingBuffer(capacity: max(1, maxLogBytes))
            process = try PTYProcess.spawn(invocation(cmd, in: dir))
        } catch {
            return Self.spawnFailure(error)
        }
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let timer = Task { [timeout] in
            try await Task.sleep(for: timeout)
            timedOut.withLock { $0 = true }
            process.terminate(graceMs: Self.killGraceMs)
        }
        let status = await withTaskCancellationHandler {
            await Self.collect(process, into: log)
        } onCancel: {
            process.terminate(graceMs: Self.killGraceMs)
        }
        timer.cancel()
        if timedOut.withLock({ $0 }) { return .timedOut }
        if status == 0 { return .passed }
        // `/usr/bin/env` reports a missing (127) or non-executable (126) tool this way: not a test failure.
        if cmd.executable == Self.envPath, status == 126 || status == 127 { return .notFound }
        let scan = ErrorScanner.extract(log.snapshot(), options: .init(maxOutputBytes: max(1, errorMaxTokens * 4)))
        return .failed(exitStatus: status, errors: scan.text.replacingOccurrences(of: "\r", with: ""),
                       truncated: scan.truncated || log.dropped > 0)
    }

    private func invocation(_ cmd: TestCommand, in dir: URL) -> ProcessInvocation {
        var env = environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["CI"] = "1"
        return ProcessInvocation(executable: cmd.executable, arguments: cmd.arguments, environment: env,
                                 workingDirectory: dir, stdin: Data())
    }

    private static func collect(_ process: PTYProcess, into log: RingBuffer) async -> Int32 {
        var status: Int32 = -1
        for await out in process.output {
            switch out {
            case .data(let chunk): log.write(chunk)
            case .exited(let code): status = code
            }
        }
        return status
    }

    private static func spawnFailure(_ error: Error) -> TestOutcome {
        if case LFCoreError.posix(let code) = error, code == ENOENT || code == EACCES { return .notFound }
        return .failed(exitStatus: -1, errors: "could not start the test command: \(error)", truncated: false)
    }
}
