//
//  AttachmentTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct AttachmentPolicyTests {
    @Test(arguments: [".env", ".env.local", ".ENV.production", "server.pem", "key.KEY", "id_rsa", "id_rsa.pub", "id_ed25519", "cert.p12",
                          ".npmrc", ".netrc", ".pypirc", "credentials", "credentials.json", "a.pfx", "my.env", ".envrc",
                          "id_ecdsa", "a.keystore", ".git-credentials"])
    func detectsSecretFiles(name: String) {
        #expect(AttachmentPolicy.isSecret(fileName: name))
    }

    @Test(arguments: ["spec-login.md", "environment.md", "env.md", "monkey.txt", "keyboard.swift", "pem.txt", "README", "notes.md2"])
    func ignoresOrdinaryFiles(name: String) {
        #expect(!AttachmentPolicy.isSecret(fileName: name))
    }

    @Test(arguments: ["/Users/a/.ssh/config", "/Users/a/.aws/config", "/Users/a/.gnupg/x.txt", "/p/.ssh/sub/readme.txt"])
    func detectsSecretDirectories(path: String) {
        #expect(AttachmentPolicy.isSecret(url: URL(fileURLWithPath: path)))
    }

    @Test func detectsSecretBehindSymlink() throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, ".ssh/id_rsa", "k")
        try TestEnv.write(dir, "plain/readme.txt", "k")
        let link = dir.appendingPathComponent("notes.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent(".ssh/id_rsa"))
        #expect(AttachmentPolicy.isSecret(url: link))
        #expect(!AttachmentPolicy.isSecret(url: dir.appendingPathComponent("plain/readme.txt")))
    }

    @Test func rejectionMessagesNameTheFileAndTheLimit() {
        #expect(DropRejection.directory.message(for: "docs").contains("docs"))
        #expect(DropRejection.tooLarge(bytes: 6 * 1024 * 1024).message(for: "big.pdf").contains("big.pdf"))
        #expect(DropRejection.tooLarge(bytes: 6 * 1024 * 1024).message(for: "big.pdf").contains("MB"))
        #expect(DropRejection.limitReached(max: 10).message(for: "x.md").contains("10"))
        #expect(DropRejection.duplicate.message(for: "x.md").contains("already"))
        #expect(!DropRejection.unreadable.message(for: "x.md").isEmpty)
        #expect(!DropRejection.notFileURL.message(for: "x").isEmpty)
    }
}

@Suite struct FileAttachmentInspectorTests {
    private let policy = AttachmentPolicy.standard
    private let inspector = FileAttachmentInspector()

    @Test func smallFileGetsATokenEstimate() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, "spec.md", String(repeating: "hello world ", count: 50))
        let info = await inspector.inspect(dir.appendingPathComponent("spec.md"), policy: policy)
        #expect(info.kind == .file)
        #expect(info.bytes == 600)
        #expect(info.isReadable)
        #expect(info.inlineTokens > 0)
    }

    @Test func largeFileIsPathOnly() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, "big.md", String(repeating: "word ", count: 20_000))
        let info = await inspector.inspect(dir.appendingPathComponent("big.md"), policy: policy)
        #expect(info.bytes == 100_000)
        #expect(info.inlineTokens == 0)
    }

    @Test func secretFileContentsAreNeverRead() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, ".env", "KEY=value\n")
        let info = await inspector.inspect(dir.appendingPathComponent(".env"), policy: policy)
        #expect(info.kind == .file)
        #expect(info.inlineTokens == 0)
    }

    @Test func directoryAndMissing() async throws {
        let dir = try TestEnv.makeTempDir()
        #expect(await inspector.inspect(dir, policy: policy).kind == .directory)
        #expect(await inspector.inspect(dir.appendingPathComponent("nope"), policy: policy).kind == .missing)
    }

    @Test func unreadableFileIsFlagged() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, "locked.md", "x")
        let url = dir.appendingPathComponent("locked.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let info = await inspector.inspect(url, policy: policy)
        #expect(!info.isReadable)
        #expect(info.inlineTokens == 0)
    }
}
