//
//  ToolsSettingsModelTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import os
import Testing
@testable import LF_AIWorkflow

@MainActor
struct ToolsSettingsModelTests {
    private let claudeURL = URL(fileURLWithPath: "/opt/bin/claude")

    private func model(found: [Tool: URL] = [:], probe: @escaping @Sendable (URL) async -> Result<String, ToolProbeError> = { _ in .success("1.0.0 (Claude Code)") }) -> ToolsSettingsModel {
        ToolsSettingsModel(
            detect: { tool, _ in
                if let url = found[tool] { return .success(url) }
                return .failure(.notFound(tool, searched: []))
            },
            probe: probe)
    }

    @Test func foundToolShowsItsPathAndNoProblem() {
        let row = ToolsSettingsModel.row(for: .claude, located: .success(claudeURL))
        #expect(row.path == "/opt/bin/claude")
        #expect(row.problem == nil)
        #expect(row.version == .unchecked)
    }

    @Test func missingToolShowsItsProblemAndNoPath() {
        let row = ToolsSettingsModel.row(for: .git, located: .failure(.notFound(.git, searched: ["/usr/bin"])))
        #expect(row.path == nil)
        #expect(row.problem?.contains("git") == true)
    }

    @Test func redetectFillsOneRowPerToolInOrder() async {
        let m = model(found: [.claude: claudeURL])
        await m.redetect(overrides: [:])
        #expect(m.rows.map(\.tool) == Tool.allCases)
        #expect(m.rows.first { $0.tool == .claude }?.path == "/opt/bin/claude")
        #expect(m.rows.first { $0.tool == .git }?.path == nil)
    }

    @Test func overridesAreForwardedToDetection() async {
        let seen = Recorder()
        let m = ToolsSettingsModel(
            detect: { tool, overrides in
                seen.record(overrides[tool])
                return .success(URL(fileURLWithPath: overrides[tool] ?? "/usr/bin/\(tool.rawValue)"))
            },
            probe: { _ in .success("x") })
        await m.redetect(overrides: [.graphify: "/opt/bin/graphify"])
        #expect(seen.values.contains("/opt/bin/graphify"))
        #expect(m.rows.first { $0.tool == .graphify }?.path == "/opt/bin/graphify")
    }

    @Test func testButtonRunsVersionAndShowsTheLine() async {
        let m = model(found: [.claude: claudeURL])
        await m.redetect(overrides: [:])
        await m.test(.claude)
        #expect(m.rows.first { $0.tool == .claude }?.version == .found("1.0.0 (Claude Code)"))
    }

    @Test func failedVersionProbeIsReported() async {
        let m = model(found: [.claude: claudeURL], probe: { _ in .failure(.exited(127)) })
        await m.redetect(overrides: [:])
        await m.test(.claude)
        #expect(m.rows.first { $0.tool == .claude }?.version == .failed("The tool exited with status 127."))
    }

    @Test func testWithoutDetectedPathDoesNothing() async {
        let m = model()
        await m.redetect(overrides: [:])
        await m.test(.git)
        #expect(m.rows.first { $0.tool == .git }?.version == .unchecked)
    }

    @Test func redetectResetsAPreviousVersionResult() async {
        let m = model(found: [.claude: claudeURL])
        await m.redetect(overrides: [:])
        await m.test(.claude)
        await m.redetect(overrides: [:])
        #expect(m.rows.first { $0.tool == .claude }?.version == .unchecked)
    }

    @Test func typedOverrideIsValidatedAsAbsolute() {
        let result = ToolsSettingsModel.validatedOverride("bin/claude", kind: { _ in .regularExecutable })
        #expect(result == .failure(.notAbsolute))
    }

    @Test func typedOverrideIsCheckedAgainstTheFileSystemProbe() {
        let probed = Recorder()
        let result = ToolsSettingsModel.validatedOverride("  /opt/bin/claude  ", resolve: { $0 }, kind: { path in
            probed.record(path)
            return .notExecutable
        })
        #expect(probed.values == ["/opt/bin/claude"])
        #expect(result == .failure(.notExecutable))
    }

    @Test func typedOverrideIsStoredOnlyWhenItIsAnExecutable() {
        let result = ToolsSettingsModel.validatedOverride("/opt/bin/claude", resolve: { $0 }, kind: { _ in .regularExecutable })
        #expect(result == .success("/opt/bin/claude"))
    }

    @Test func versionLineIsTheFirstNonEmptyStdoutLine() {
        let data = Data("\n  claude 2.1.0  \nmore\n".utf8)
        #expect(ToolVersionProbe.versionLine(from: data) == "claude 2.1.0")
        #expect(ToolVersionProbe.versionLine(from: Data("  \n".utf8)) == nil)
    }
}

/// Collects values from `@Sendable` closures in a test.
private final class Recorder: Sendable {
    private let stored = OSAllocatedUnfairLock(initialState: [String?]())
    func record(_ value: String?) { stored.withLock { $0.append(value) } }
    var values: [String?] { stored.withLock { $0 } }
}
