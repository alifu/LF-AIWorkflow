//
//  GitClient.swift
//  LF-AIWorkflow
//

import Foundation

/// Thin wrapper over the `git` CLI. Every call goes through `CommandRunner` (no shell, argv only).
nonisolated struct GitClient: GitWorking {
    /// Lockfiles, generated and build output the Review stage never needs (token rule: filtered diff).
    /// `.claude/plans/**` holds the Plan stage's file (TD-109): it is task input, not work to review.
    static let reviewExcludes: [String] = [
        "**/*.lock", "**/package-lock.json", "**/yarn.lock", "**/pnpm-lock.yaml", "**/Package.resolved",
        "**/Podfile.lock", "**/gradle.lockfile", "**/build/**", "**/DerivedData/**", "**/*.generated.*",
        "**/*.pb.swift", "design/raw/**", "graphify-out/**", ".claude/plans/**",
    ].map { ":(exclude,glob)" + $0 }

    /// Untracked or changed secrets must never reach the Review prompt.
    static let secretExcludes: [String] = [
        "**/.env*", "**/*.pem", "**/*.key", "**/id_rsa*", "**/id_ed25519*", "**/*.p12", "**/*.pfx", "**/*.keystore",
    ].map { ":(exclude,glob)" + $0 }

    /// Only these `GIT_*` variables survive: every other one can redirect git, inject config
    /// (`GIT_CONFIG_*`, `GIT_SSH_COMMAND`, `GIT_EXTERNAL_DIFF`, ...) or point it at another repository.
    private static let allowedGitVariables: Set<String> = ["GIT_TERMINAL_PROMPT", "GIT_PAGER"]

    /// `git diff --no-index` exit status for a file it cannot hash (permissions, vanished file).
    private static let unreadableStatus: Int32 = 128

    private static let baseOptions = ["--no-pager", "-c", "core.quotepath=off", "-c", "color.ui=false",
                                    "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "diff.external="]

    private let locators: ToolLocatorProvider
    private let timeout: Duration
    private let environment: [String: String]
    private let untrackedByteLimit: Int

    /// Total bytes of untracked-file diffs added to one review diff (each file is already capped by `CommandRunner`).
    static let defaultUntrackedByteLimit = 16 * 1024 * 1024

    init(locator: ToolLocator, timeout: Duration = .seconds(30),
         environment: [String: String] = ProcessInfo.processInfo.environment,
         untrackedByteLimit: Int = GitClient.defaultUntrackedByteLimit) {
        self.init(locators: ToolLocatorProvider(fixed: locator), timeout: timeout,
                  environment: environment, untrackedByteLimit: untrackedByteLimit)
    }

    /// The locator is asked per command, so a changed `git` path applies to the next call.
    init(locators: ToolLocatorProvider, timeout: Duration = .seconds(30),
         environment: [String: String] = ProcessInfo.processInfo.environment,
         untrackedByteLimit: Int = GitClient.defaultUntrackedByteLimit) {
        self.untrackedByteLimit = untrackedByteLimit
        self.locators = locators
        self.timeout = timeout
        self.environment = Self.scrubbed(environment)
    }

    /// Drops every `GIT_*` variable except the two allowed ones, then pins those.
    /// Complexity: O(n) time, O(n) space
    static func scrubbed(_ environment: [String: String]) -> [String: String] {
        var env = environment.filter { !$0.key.hasPrefix("GIT_") || allowedGitVariables.contains($0.key) }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        return env
    }

    /// Runs `git <args>` in `dir` and returns stdout. Non-zero exit becomes `.commandFailed` (or `.notARepository`).
    /// Complexity: O(n) time in output bytes, O(n) space
    func run(_ args: [String], in dir: URL) async throws(GitError) -> String {
        try await run(args, in: dir, okStatuses: [0])
    }

    /// Like `run(_:in:)`, but every status in `okStatuses` counts as success (`diff --no-index` exits 1 on a difference).
    /// Complexity: O(n) time in output bytes, O(n) space
    private func run(_ args: [String], in dir: URL, okStatuses: Set<Int32> = [0],
                     extraEnvironment: [String: String] = [:]) async throws(GitError) -> String {
        let executable: URL
        do { executable = try await locators.current().locate(.git) } catch { throw .gitNotFound }
        let invocation = ProcessInvocation(executable: executable, arguments: Self.baseOptions + args,
                                           environment: environment.merging(extraEnvironment) { _, new in new },
                                           workingDirectory: dir, stdin: Data())
        let result: CommandResult
        do {
            result = try await CommandRunner.run(invocation, timeout: timeout)
        } catch {
            switch error {
            case .timedOut: throw .timedOut
            case .spawnFailed(let message): throw .commandFailed(args: args, status: -1, stderr: message)
            }
        }
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        guard okStatuses.contains(result.status) else {
            let stderr = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("not a git repository") { throw .notARepository(dir.path) }
            throw .commandFailed(args: args, status: result.status, stderr: stderr)
        }
        return result.truncated ? stdout + "\n[output truncated]\n" : stdout
    }

    /// Complexity: O(1) time, O(1) space
    func headCommit(in dir: URL) async throws(GitError) -> String {
        try await run(["rev-parse", "HEAD"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Records all uncommitted work, tracked and untracked, as a dangling commit without touching the tree, the real
    /// index or the stash list: a temporary index (`GIT_INDEX_FILE`) is seeded from HEAD, `add -A` stages the tree
    /// (minus review noise and secret paths) into it, `write-tree` and `commit-tree` make the commit. A clean tree gives HEAD; any failure (for example
    /// no committer identity) falls back to HEAD.
    /// Complexity: O(files) time, O(1) space
    func snapshotCommit(in dir: URL) async throws(GitError) -> String {
        let head = try await headCommit(in: dir)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lf-snapshot-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true) } catch { return head }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = ["GIT_INDEX_FILE": scratch.appendingPathComponent("index").path]
        do {
            _ = try await run(["read-tree", head], in: dir, extraEnvironment: index)
            _ = try await run(["add", "-A", "--", "."] + Self.reviewExcludes + Self.secretExcludes, in: dir,
                              extraEnvironment: index)
            let tree = try await run(["write-tree"], in: dir, extraEnvironment: index).trimmingCharacters(in: .whitespacesAndNewlines)
            let headTree = try await run(["rev-parse", "\(head)^{tree}"], in: dir).trimmingCharacters(in: .whitespacesAndNewlines)
            if tree == headTree { return head }
            let created = try await run(["commit-tree", tree, "-p", head, "-m", "lf-aiworkflow review base"], in: dir)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard created.count == 40, created.allSatisfy(\.isHexDigit) else { return head }
            return created
        } catch {
            return head
        }
    }

    /// Complexity: O(1) time, O(1) space
    func isRepository(_ dir: URL) async -> Bool {
        let inside = try? await run(["rev-parse", "--is-inside-work-tree"], in: dir)
        return inside?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Uncommitted work counts. With `markNewFiles` (task worktrees only) `git add -A --intent-to-add` makes new
    /// files visible to `git diff <base>`; otherwise the index is never touched and each untracked file is diffed
    /// against /dev/null. Noise and secret paths are excluded either way.
    /// Complexity: O(files + diff bytes) time, O(diff bytes) space
    func reviewDiff(in dir: URL, base: String, markNewFiles: Bool) async throws(GitError) -> String {
        guard !base.isEmpty, !base.hasPrefix("-") else {
            throw .commandFailed(args: ["diff", base], status: -1, stderr: "invalid base revision")
        }
        let excludes = Self.reviewExcludes + Self.secretExcludes
        let diffOptions = ["diff", "--no-ext-diff", "--no-textconv"]
        if markNewFiles {
            _ = try await run(["add", "-A", "--intent-to-add", "--", "."] + excludes, in: dir)
            return try await run(diffOptions + [base, "--", "."] + excludes, in: dir)
        }
        let listing = try await run(["ls-files", "--others", "--exclude-standard", "-z", "--", "."] + excludes, in: dir)
        let (files, heldByBase) = try await splitUntracked(listing.split(separator: "\0").map(String.init), base: base, in: dir)
        // Untracked files the snapshot already holds look deleted to `git diff <base>` (they are not in the real index).
        let hidden = heldByBase.map { ":(exclude,literal)" + $0 }
        var output = try await run(diffOptions + [base, "--", "."] + excludes + hidden, in: dir)
        var untrackedBytes = 0
        for (index, file) in files.enumerated() {
            if untrackedBytes >= untrackedByteLimit {
                output += "[omitted \(files.count - index) more untracked files: size limit]\n"
                break
            }
            do {
                let piece = try await run(diffOptions + ["--no-index", "--", "/dev/null", file], in: dir, okStatuses: [0, 1])
                untrackedBytes += piece.utf8.count
                output += piece
            } catch .commandFailed(_, Self.unreadableStatus, _) {
                output += "[skipped \(file): unreadable]\n"
            }
        }
        return output
    }

    /// Splits untracked files into those new or changed since the base and those the base snapshot already holds
    /// (TD-117: task-start state, not work to review). Held files whose content changed stay in `changed` too.
    /// Complexity: O(files) time, O(files) space
    private func splitUntracked(_ files: [String], base: String, in dir: URL)
        async throws(GitError) -> (changed: [String], heldByBase: [String]) {
        guard !files.isEmpty else { return ([], []) }
        let inBase = Set(try await run(["ls-tree", "-r", "-z", "--name-only", base], in: dir).split(separator: "\0").map(String.init))
        var changed: [String] = [], held: [String] = []
        for file in files {
            guard inBase.contains(file) else { changed.append(file); continue }
            held.append(file)
            let current = try? await run(["hash-object", "--no-filters", "--", file], in: dir)
            let baseline = try? await run(["rev-parse", "\(base):\(file)"], in: dir)
            if current == nil || current != baseline { changed.append(file) }
        }
        return (changed, held)
    }
}
