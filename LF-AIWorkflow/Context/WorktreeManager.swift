//
//  WorktreeManager.swift
//  LF-AIWorkflow
//

import Foundation

/// Creates, lists and removes one git worktree per task, as siblings of the repo: `../<repo>-<slug>` on branch
/// `ai/<slug>`. Every git command runs in the repo given by the caller and only touches worktree bookkeeping; the
/// user's main checkout (files, index, HEAD) is never modified. Branches are never deleted.
nonisolated struct WorktreeManager: WorktreeProviding {
    static let branchPrefix = "ai/"
    private static let maxNameAttempts = 20
    private static let fallbackSlug = "task"

    private let git: GitClient

    init(git: GitClient) { self.git = git }

    /// Lowercase `[a-z0-9-]`, runs of other characters collapse to one dash, no leading/trailing dash,
    /// at most `maxLength` characters, `"task"` when nothing is left.
    /// Complexity: O(n) time, O(n) space
    static func slug(for title: String, maxLength: Int = 40) -> String {
        var out = ""
        var pendingDash = false
        for scalar in title.lowercased().unicodeScalars {
            if scalar.isASCII, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        var capped = String(out.prefix(max(1, maxLength)))
        while capped.hasSuffix("-") { capped.removeLast() }
        return capped.isEmpty ? fallbackSlug : capped
    }

    /// `realpath(3)` form of `url` (git reports canonical paths; `URL.resolvingSymlinksInPath` maps `/private/var`
    /// back to `/var`, so it cannot be compared with git's output). Falls back to the standardized path.
    /// Complexity: O(p) time, O(p) space (p = path length)
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// A slug is safe when it starts with a letter or digit and holds only `[a-z0-9-]`: no leading `-`, no `..`,
    /// no separators.
    /// Complexity: O(n) time, O(1) space
    static func isSafe(slug: String) -> Bool {
        guard let first = slug.unicodeScalars.first, first != "-" else { return false }
        return slug.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// `git worktree add ../<repo>-<slug> -b ai/<slug> HEAD`; `baseCommit` is HEAD before the add. A taken path or
    /// branch gets `-2`, `-3`, ... (up to 20 names), then `.branchExists`.
    /// Complexity: O(1) git calls (at most 20 name probes), O(1) space
    func create(repo: URL, slug: String) async throws(GitError) -> Worktree {
        guard Self.isSafe(slug: slug) else {
            throw .commandFailed(args: ["worktree", "add"], status: -1, stderr: "invalid worktree name: \(slug)")
        }
        let base = try await git.headCommit(in: repo)
        let root = Self.canonical(repo)
        for attempt in 1...Self.maxNameAttempts {
            let name = attempt == 1 ? slug : "\(slug)-\(attempt)"
            let branch = Self.branchPrefix + name
            let path = root.deletingLastPathComponent()
                .appendingPathComponent("\(root.lastPathComponent)-\(name)", isDirectory: true)
            if FileManager.default.fileExists(atPath: path.path) { continue }
            if try await branchExists(branch, repo: repo) { continue }
            _ = try await git.run(["worktree", "add", "-b", branch, path.path, base], in: repo)
            return Worktree(path: path, branch: branch, baseCommit: base)
        }
        throw .branchExists(Self.branchPrefix + slug)
    }

    /// All worktrees of `repo` (main checkout included) from `git worktree list --porcelain`.
    /// Complexity: O(w) time, O(w) space (w = worktrees)
    func list(repo: URL) async throws(GitError) -> [Worktree] {
        Self.parse(try await git.run(["worktree", "list", "--porcelain"], in: repo))
    }

    /// Removes the worktree directory. Refuses the main checkout and anything git does not list as a linked
    /// worktree of `repo`. Dirty trees need `force`. The branch stays.
    /// Complexity: O(w) time plus the removal, O(w) space
    func remove(_ wt: Worktree, repo: URL, force: Bool) async throws(GitError) {
        let target = Self.canonical(wt.path).path
        let all = try await list(repo: repo)
        guard let main = all.first, Self.canonical(main.path).path != target,
              all.contains(where: { Self.canonical($0.path).path == target }) else {
            throw .commandFailed(args: ["worktree", "remove"], status: -1,
                                 stderr: "refusing to remove a path that is not a linked worktree: \(wt.path.path)")
        }
        _ = try await git.run(["worktree", "remove"] + (force ? ["--force"] : []) + [target], in: repo)
    }

    private func branchExists(_ branch: String, repo: URL) async throws(GitError) -> Bool {
        do {
            _ = try await git.run(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo)
            return true
        } catch {
            if case .commandFailed(_, 1, _) = error { return false }
            throw error
        }
    }

    private static func parse(_ porcelain: String) -> [Worktree] {
        var result: [Worktree] = []
        var path: String?, head = "", branch = "", bare = false
        func flush() {
            if let path, !bare { result.append(Worktree(path: URL(fileURLWithPath: path, isDirectory: true), branch: branch, baseCommit: head)) }
            (path, head, branch, bare) = (nil, "", "", false)
        }
        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") { flush(); path = String(line.dropFirst(9)) }
            else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
            else if line.hasPrefix("branch ") { branch = String(line.dropFirst(7).replacingOccurrences(of: "refs/heads/", with: "")) }
            else if line == "bare" { bare = true }
        }
        flush()
        return result
    }
}
