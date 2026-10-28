//
//  TestHelpers.swift
//  LF-AIWorkflowTests
//

import Foundation
@testable import LF_AIWorkflow

/// Shared fixtures for Phase 4 suites: temp dirs, fake CLIs, temp git repos. All spawns go through `CommandRunner`.
enum TestEnv {
    /// Environment for git in tests: no user or system config.
    static let git: [String: String] = [
        "PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory(),
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
    ]

    static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func writeExecutable(_ dir: URL, _ name: String, body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func write(_ dir: URL, _ relative: String, _ text: String) throws {
        let url = dir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func git(_ args: [String], in dir: URL) async throws -> String {
        let inv = ProcessInvocation(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-c", "user.name=lf", "-c", "user.email=lf@example.invalid", "-c", "commit.gpgsign=false"] + args,
            environment: git, workingDirectory: dir, stdin: Data())
        let result = try await CommandRunner.run(inv, timeout: .seconds(30))
        guard result.status == 0 else {
            throw CommandError.spawnFailed("git \(args) failed: \(String(decoding: result.stderr, as: UTF8.self))")
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    /// A repo with one commit containing `a.swift` and `Package.resolved`.
    static func makeRepo() async throws -> URL {
        let dir = try makeTempDir()
        try await git(["init", "-q", "-b", "main"], in: dir)
        try write(dir, "a.swift", "let a = 1\n")
        try write(dir, "Package.resolved", "{}\n")
        try await git(["add", "-A"], in: dir)
        try await git(["commit", "-q", "-m", "init"], in: dir)
        return dir
    }

    static func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    /// Polls for a pid file written by a fake script.
    static func readPid(_ url: URL, attempts: Int = 100) async throws -> Int32? {
        for _ in 0..<attempts {
            if let s = try? String(contentsOf: url, encoding: .utf8),
               let p = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return p }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    static func waitUntilGone(_ pid: Int32, attempts: Int = 80) async throws -> Bool {
        for _ in 0..<attempts {
            if !alive(pid) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
