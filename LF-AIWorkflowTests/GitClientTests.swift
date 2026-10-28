//
//  GitClientTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(2)))
struct GitClientTests {
    private func client(timeout: Duration = .seconds(30)) -> GitClient {
        GitClient(locator: ToolLocator(searchPath: ["/usr/bin"]), timeout: timeout, environment: TestEnv.git)
    }

    @Test func headCommitIs40Hex() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let head = try await client().headCommit(in: repo)
        #expect(head.count == 40)
        #expect(head.allSatisfy { $0.isHexDigit })
    }

    @Test func isRepositoryDistinguishesDirs() async throws {
        let repo = try await TestEnv.makeRepo()
        let plain = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: plain) }
        #expect(await client().isRepository(repo))
        #expect(await !client().isRepository(plain))
    }

    @Test func diffIncludesModifiedAndNewUntrackedFiles() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "a.swift", "let a = 2\n")
        try TestEnv.write(repo, "new.swift", "let fresh = 3\n")
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: true)
        #expect(diff.contains("+let a = 2"))
        #expect(diff.contains("new.swift"))
        #expect(diff.contains("+let fresh = 3"))
    }

    @Test func diffExcludesNoisePaths() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "Package.resolved", "{\"changed\": true}\n")
        try TestEnv.write(repo, "build/x.o", "obj\n")
        try TestEnv.write(repo, "design/raw/a.svg", "<svg/>\n")
        try TestEnv.write(repo, "sub/yarn.lock", "lock\n")
        try TestEnv.write(repo, "graphify-out/graph.json", "{}\n")
        try TestEnv.write(repo, "keep.swift", "let keep = 1\n")
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: true)
        #expect(diff.contains("keep.swift"))
        for noise in ["Package.resolved", "build/x.o", "design/raw/a.svg", "yarn.lock", "graph.json"] {
            #expect(!diff.contains(noise), "\(noise) leaked into the diff")
        }
    }

    @Test func nonRepositoryThrowsNotARepository() async throws {
        let plain = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: plain) }
        do {
            _ = try await client().headCommit(in: plain)
            Issue.record("expected throw")
        } catch {
            guard case .notARepository = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func missingGitThrowsGitNotFound() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = GitClient(locator: ToolLocator(searchPath: []), environment: TestEnv.git)
        await #expect(throws: GitError.gitNotFound) { _ = try await c.headCommit(in: dir) }
    }

    @Test func badBaseRefCarriesStderr() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        do {
            _ = try await client().reviewDiff(in: repo, base: "no-such-ref", markNewFiles: true)
            Issue.record("expected throw")
        } catch {
            guard case .commandFailed(_, let status, let stderr) = error else { Issue.record("wrong error \(error)"); return }
            #expect(status != 0)
            #expect(!stderr.isEmpty)
        }
    }

    @Test func baseStartingWithDashIsRejected() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        do {
            _ = try await client().reviewDiff(in: repo, base: "--output=/tmp/lf-evil", markNewFiles: true)
            Issue.record("expected throw")
        } catch {
            guard case .commandFailed = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func twoMegabyteDiffCompletes() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        let big = String(repeating: "let x = 1234567890123456789012345678901234567890\n", count: 45_000)
        try TestEnv.write(repo, "big.swift", big)
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: true)
        #expect(diff.utf8.count > 2_000_000)
        #expect(diff.hasPrefix("diff --git"))
    }

    @Test func reviewExcludesListIsGlobPathspecs() {
        #expect(GitClient.reviewExcludes.count == 13)
        #expect(GitClient.reviewExcludes.allSatisfy { $0.hasPrefix(":(exclude,glob)") })
        #expect(GitClient.reviewExcludes.contains(":(exclude,glob)graphify-out/**"))
    }

    // MARK: review fixes

    private func status(_ repo: URL) async throws -> String {
        try await TestEnv.git(["status", "--porcelain"], in: repo)
    }

    @Test func noMarkingLeavesIndexUntouchedButIncludesUntrackedContent() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "a.swift", "let a = 2\n")
        try TestEnv.write(repo, "new.swift", "let fresh = 3\n")
        let before = try await status(repo)
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: false)
        #expect(try await status(repo) == before)
        #expect(before.contains("?? new.swift"))
        #expect(diff.contains("+let a = 2"))
        #expect(diff.contains("diff --git a/new.swift b/new.swift"))
        #expect(diff.contains("+let fresh = 3"))
    }

    @Test func secretsNeverAppearInEitherPath() async throws {
        let secrets = [".env": "API_KEY=sekrit1", "sub/.env.local": "T=sekrit2", "k.pem": "sekrit3", "x/a.key": "sekrit4",
                       "id_rsa": "sekrit5", "id_ed25519.pub": "sekrit6", "c.p12": "sekrit7", "c.pfx": "sekrit8",
                       "app.keystore": "sekrit9"]
        for mark in [true, false] {
            let repo = try await TestEnv.makeRepo()
            defer { try? FileManager.default.removeItem(at: repo) }
            let base = try await client().headCommit(in: repo)
            for (path, text) in secrets { try TestEnv.write(repo, path, text + "\n") }
            try TestEnv.write(repo, "keep.swift", "let keep = 1\n")
            let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: mark)
            #expect(diff.contains("+let keep = 1"))
            #expect(!diff.contains("sekrit"), "secret content leaked (markNewFiles: \(mark))")
            #expect(!diff.contains(".env"))
        }
    }

    @Test func ambientGitEnvironmentIsIgnored() async throws {
        let repo = try await TestEnv.makeRepo()
        let other = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: repo); try? FileManager.default.removeItem(at: other) }
        var env = TestEnv.git
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                    "GIT_ALTERNATE_OBJECT_DIRECTORIES"] { env[key] = other.appendingPathComponent("nope").path }
        let c = GitClient(locator: ToolLocator(searchPath: ["/usr/bin"]), environment: env)
        let head = try await c.headCommit(in: repo)
        #expect(head.count == 40)
    }

    @Test func untrackedDiffsStopAtTotalLimitWithNote() async throws {
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let base = try await client().headCommit(in: repo)
        for name in ["u1", "u2", "u3", "u4"] { try TestEnv.write(repo, "\(name).txt", String(repeating: "x", count: 400) + "\n") }
        let limited = GitClient(locator: ToolLocator(searchPath: ["/usr/bin"]), environment: TestEnv.git, untrackedByteLimit: 600)
        let diff = try await limited.reviewDiff(in: repo, base: base, markNewFiles: false)
        #expect(diff.contains("[omitted 2 more untracked files: size limit]"))
        #expect(diff.contains("u1.txt"))
        #expect(!diff.contains("u4.txt"))
    }

    @Test func unreadableUntrackedFileIsSkippedWithNote() async throws {
        let repo = try await TestEnv.makeRepo()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: repo.appendingPathComponent("a_secret.txt").path)
            try? FileManager.default.removeItem(at: repo)
        }
        let base = try await client().headCommit(in: repo)
        try TestEnv.write(repo, "a_secret.txt", "hidden\n")
        try TestEnv.write(repo, "b_ok.txt", "visible\n")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: repo.appendingPathComponent("a_secret.txt").path)
        let diff = try await client().reviewDiff(in: repo, base: base, markNewFiles: false)
        #expect(diff.contains("[skipped a_secret.txt: unreadable]"))
        #expect(diff.contains("+visible"))
    }
}
