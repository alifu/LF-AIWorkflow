//
//  SettingsValidationTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct SettingsValidationTests {
    // MARK: - Numbers

    @Test func wholeNumberInsideRangeIsAcceptedWithoutMessage() {
        #expect(SettingsValidation.parse(" 42 ", range: 1...200, label: "Max turns") == .value(42, message: nil))
    }

    @Test func numberAboveRangeIsClampedWithVisibleMessage() {
        let outcome = SettingsValidation.parse("500", range: 1...200, label: "Max turns")
        #expect(outcome == .value(200, message: "Max turns must be between 1 and 200; using 200."))
    }

    @Test func numberBelowRangeIsClampedWithVisibleMessage() {
        let outcome = SettingsValidation.parse("0", range: 1...200, label: "Max turns")
        #expect(outcome == .value(1, message: "Max turns must be between 1 and 200; using 1."))
    }

    @Test(arguments: ["", "   ", "ten", "1.5", "99999999999999999999999"])
    func nonNumericTextIsRejected(text: String) {
        let outcome = SettingsValidation.parse(text, range: 1...200, label: "Max turns")
        #expect(outcome == .invalid("Max turns must be a whole number."))
    }

    @Test func clampHonoursBothBounds() {
        #expect(SettingsValidation.clamp(-3, to: 0...10) == 0)
        #expect(SettingsValidation.clamp(11, to: 0...10) == 10)
        #expect(SettingsValidation.clamp(5, to: 0...10) == 5)
    }

    @Test func limitsMatchTheDocumentedRanges() {
        #expect(SettingsLimits.maxTurns == 1...200)
        #expect(SettingsLimits.taskTokens.lowerBound == 1)
        #expect(SettingsLimits.dayTokens.lowerBound == 0)
        #expect(SettingsLimits.promptTokens.lowerBound > 0)
    }

    // MARK: - Models

    @Test func onlyKnownModelNamesAreAccepted() {
        #expect(KnownModels.all == ["opus", "sonnet", "haiku"])
        #expect(SettingsValidation.isKnownModel("sonnet"))
        #expect(!SettingsValidation.isKnownModel(""))
        #expect(!SettingsValidation.isKnownModel("sonnet --dangerously-skip-permissions"))
        #expect(!SettingsValidation.isKnownModel("Opus"))
    }

    // MARK: - Tool paths (shape, before any file access)

    @Test func emptyPathIsRejected() {
        #expect(ToolPathValidator.validate("  ", kind: { _ in .regularExecutable }) == .failure(.empty))
    }

    @Test func relativePathIsRejectedWithoutTouchingTheFileSystem() {
        let probe: (String) -> ToolFileKind = { _ in
            Issue.record("the file system must not be probed for a relative path")
            return .regularExecutable
        }
        #expect(ToolPathValidator.validate("bin/claude", kind: probe) == .failure(.notAbsolute))
    }

    @Test func controlCharactersAreRejected() {
        #expect(ToolPathValidator.validate("/usr/bin/git\n--help", kind: { _ in .regularExecutable }) == .failure(.invalidCharacters))
    }

    @Test(arguments: [
        (ToolFileKind.missing, ToolPathError.missing),
        (ToolFileKind.notRegularFile, ToolPathError.notRegularFile),
        (ToolFileKind.notExecutable, ToolPathError.notExecutable),
    ])
    func probeKindMapsToItsError(kind: ToolFileKind, error: ToolPathError) {
        #expect(ToolPathValidator.validate("/opt/bin/claude", kind: { _ in kind }) == .failure(error))
    }

    @Test func absoluteExecutableRegularFileIsAcceptedTrimmed() {
        #expect(ToolPathValidator.validate(" /opt/homebrew/bin/git ", resolve: { $0 }, kind: { _ in .regularExecutable }) == .success("/opt/homebrew/bin/git"))
    }

    @Test func everyPathErrorHasAUserMessage() {
        let errors: [ToolPathError] = [.empty, .notAbsolute, .invalidCharacters, .missing, .notRegularFile, .notExecutable]
        #expect(errors.allSatisfy { !$0.message.isEmpty })
    }

    @Test func realProbeRejectsDirectoriesAndMissingFiles() throws {
        let dir = try TestEnv.makeTempDir()
        #expect(ToolPathValidator.kind(atPath: dir.path) == .notRegularFile)
        #expect(ToolPathValidator.kind(atPath: dir.appendingPathComponent("nope").path) == .missing)
    }

    @Test func symlinkedToolIsStoredAsItsResolvedPath() throws {
        let dir = try TestEnv.makeTempDir()
        let tool = dir.appendingPathComponent("real-tool")
        let link = dir.appendingPathComponent("link-tool")
        try Data().write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        let expected = tool.resolvingSymlinksInPath().path
        #expect(ToolPathValidator.validate(link.path, kind: ToolPathValidator.kind(atPath:)) == .success(expected))
    }

    @Test func realProbeAcceptsExecutableFileOnly() throws {
        let dir = try TestEnv.makeTempDir()
        let plain = dir.appendingPathComponent("plain")
        let tool = dir.appendingPathComponent("tool")
        try Data().write(to: plain)
        try Data().write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(ToolPathValidator.kind(atPath: plain.path) == .notExecutable)
        #expect(ToolPathValidator.kind(atPath: tool.path) == .regularExecutable)
    }

    // MARK: - Store clamps use the same limits

    @MainActor @Test func storeClampsTaskBudgetToAtLeastOneToken() {
        let store = SettingsStore(suiteName: "lf-validation-\(UUID().uuidString)")
        store.taskBudget = 0
        #expect(store.taskBudget == SettingsLimits.taskTokens.lowerBound)
    }

    @MainActor @Test func storeDropsUnknownModelNames() {
        let store = SettingsStore(suiteName: "lf-validation-\(UUID().uuidString)")
        store.stageModels = [.plan: "opus", .code: "gpt-4"]
        #expect(store.stageModels == [.plan: "opus"])
    }

    @MainActor @Test func storeClampsPromptCapsToTheirRange() {
        let store = SettingsStore(suiteName: "lf-validation-\(UUID().uuidString)")
        store.promptCaps = [.review: 10]
        #expect(store.promptCaps[.review] == SettingsLimits.promptTokens.lowerBound)
    }
}
