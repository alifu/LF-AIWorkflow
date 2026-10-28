//
//  WorktreeManagerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(3)))
struct WorktreeManagerTests {
    private func manager(searchPath: [String] = ["/usr/bin"]) -> WorktreeManager {
        WorktreeManager(git: GitClient(locator: ToolLocator(searchPath: searchPath), environment: TestEnv.git))
    }

    /// A repo inside its own temp parent so `../<repo>-<slug>` stays in the test's directory.
    private func makeRepoInParent() async throws -> (parent: URL, repo: URL) {
        let parent = WorktreeManager.canonical(try TestEnv.makeTempDir())
        let repo = parent.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await TestEnv.git(["init", "-q", "-b", "main"], in: repo)
        try TestEnv.write(repo, "a.swift", "let a = 1\n")
        try await TestEnv.git(["add", "-A"], in: repo)
        try await TestEnv.git(["commit", "-q", "-m", "init"], in: repo)
        return (parent, repo)
    }

    @Test(arguments: [
        ("Add Login Screen", "add-login-screen"),
        ("  --Fix: the bug!!  ", "fix-the-bug"),
        ("Café ünïcode", "caf-n-code"),
        ("🚀🚀 ship it 🚀", "ship-it"),
        ("a///b___c", "a-b-c"),
        ("!!!???", "task"),
        ("", "task"),
        ("../../etc/passwd", "etc-passwd"),
    ])
    func slugTable(title: String, expected: String) {
        #expect(WorktreeManager.slug(for: title) == expected)
    }

    @Test func slugIsCappedWithoutTrailingDash() {
        let slug = WorktreeManager.slug(for: String(repeating: "ab ", count: 100))
        #expect(slug.count <= 40)
        #expect(!slug.hasSuffix("-"))
        #expect(!slug.isEmpty)
        let long = WorktreeManager.slug(for: String(repeating: "x", count: 200))
        #expect(long.count == 40)
    }

    @Test func createMakesDirectoryBranchAndBaseCommit() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let wt = try await manager().create(repo: repo, slug: "feature")
        let head = try await TestEnv.git(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(FileManager.default.fileExists(atPath: wt.path.appendingPathComponent("a.swift").path))
        #expect(wt.path.lastPathComponent == "proj-feature")
        #expect(wt.path.deletingLastPathComponent().path == parent.path)
        #expect(wt.branch == "ai/feature")
        #expect(wt.baseCommit == head)
        let branch = try await TestEnv.git(["rev-parse", "--abbrev-ref", "HEAD"], in: wt.path)
        #expect(branch.trimmingCharacters(in: .whitespacesAndNewlines) == "ai/feature")
    }

    @Test func secondCreateWithSameSlugGetsSuffix() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let first = try await manager().create(repo: repo, slug: "dup")
        let second = try await manager().create(repo: repo, slug: "dup")
        let third = try await manager().create(repo: repo, slug: "dup")
        #expect(first.branch == "ai/dup")
        #expect(second.branch == "ai/dup-2")
        #expect(third.branch == "ai/dup-3")
        #expect(second.path.lastPathComponent == "proj-dup-2")
    }

    @Test func existingBranchAloneForcesSuffix() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        try await TestEnv.git(["branch", "ai/taken"], in: repo)
        let wt = try await manager().create(repo: repo, slug: "taken")
        #expect(wt.branch == "ai/taken-2")
    }

    @Test(arguments: ["-rf", "a..b", "..", "", "UPPER", "a/b", "a b", "-"])
    func createRejectsUnsafeSlug(slug: String) async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        await #expect(throws: GitError.self) { _ = try await manager().create(repo: repo, slug: slug) }
        let entries = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(entries == ["proj"])
    }

    @Test func listIncludesCreatedWorktree() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let wt = try await manager().create(repo: repo, slug: "listed")
        let all = try await manager().list(repo: repo)
        #expect(all.contains { $0.path == wt.path && $0.branch == "ai/listed" })
        #expect(all.count == 2)
    }

    @Test func removeDeletesDirectoryButKeepsBranch() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let wt = try await manager().create(repo: repo, slug: "gone")
        try await manager().remove(wt, repo: repo, force: false)
        #expect(!FileManager.default.fileExists(atPath: wt.path.path))
        let branches = try await TestEnv.git(["branch", "--list", "ai/gone"], in: repo)
        #expect(branches.contains("ai/gone"))
    }

    @Test func removeDirtyWorktreeNeedsForce() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let wt = try await manager().create(repo: repo, slug: "dirty")
        try TestEnv.write(wt.path, "a.swift", "let a = 99\n")
        try TestEnv.write(wt.path, "untracked.txt", "x")
        do {
            try await manager().remove(wt, repo: repo, force: false)
            Issue.record("expected failure")
        } catch {
            guard case .commandFailed = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(FileManager.default.fileExists(atPath: wt.path.path))
        try await manager().remove(wt, repo: repo, force: true)
        #expect(!FileManager.default.fileExists(atPath: wt.path.path))
    }

    @Test func removeRefusesMainCheckoutAndForeignPaths() async throws {
        let (parent, repo) = try await makeRepoInParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let main = Worktree(path: repo, branch: "main", baseCommit: "x")
        await #expect(throws: GitError.self) { try await manager().remove(main, repo: repo, force: true) }
        let foreign = Worktree(path: parent.appendingPathComponent("elsewhere"), branch: "ai/x", baseCommit: "x")
        await #expect(throws: GitError.self) { try await manager().remove(foreign, repo: repo, force: true) }
        #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("a.swift").path))
    }

    @Test func nonRepositoryThrowsNotARepository() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await manager().create(repo: dir, slug: "x")
            Issue.record("expected failure")
        } catch {
            guard case .notARepository = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func missingGitThrowsGitNotFound() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await manager(searchPath: [dir.path]).create(repo: dir, slug: "x")
            Issue.record("expected failure")
        } catch {
            #expect(error == .gitNotFound)
        }
    }

    @Test func repoWithoutCommitsFailsReadably() async throws {
        let parent = WorktreeManager.canonical(try TestEnv.makeTempDir())
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = parent.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await TestEnv.git(["init", "-q", "-b", "main"], in: repo)
        do {
            _ = try await manager().create(repo: repo, slug: "x")
            Issue.record("expected failure")
        } catch {
            guard case .commandFailed(_, _, let stderr) = error else { Issue.record("wrong error \(error)"); return }
            #expect(!stderr.isEmpty)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["empty"])
    }
}
