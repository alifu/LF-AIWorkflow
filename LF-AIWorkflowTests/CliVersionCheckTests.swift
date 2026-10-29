//
//  CliVersionCheckTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct CliVersionCheckTests {
    @Test func pinnedVersionMatchesTheRecordedFixtureFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/claude_fixtures_version.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(CliVersionCheck.version(in: text) == CliVersionCheck.pinnedClaudeVersion)
    }

    @Test func parsesTheLeadingVersionToken() {
        #expect(CliVersionCheck.version(in: "2.1.312 (Claude Code)") == "2.1.312")
        #expect(CliVersionCheck.version(in: "claude 3.0.1") == "3.0.1")
        #expect(CliVersionCheck.version(in: "no digits") == nil)
    }

    @Test func matchingVersionHasNoWarning() {
        #expect(CliVersionCheck.warning(forVersionLine: "2.1.312 (Claude Code)") == nil)
    }

    @Test func differingVersionWarnsWithBothVersions() throws {
        let text = try #require(CliVersionCheck.warning(forVersionLine: "2.2.0 (Claude Code)"))
        #expect(text.contains("2.2.0") && text.contains(CliVersionCheck.pinnedClaudeVersion))
    }

    @Test func unparsableLineGivesNoWarning() {
        #expect(CliVersionCheck.warning(forVersionLine: "garbage") == nil)
    }

    @Test func claudeRowWarnsAfterAVersionTestButOtherToolsDoNot() async {
        let url = URL(fileURLWithPath: "/opt/bin/tool")
        let m = ToolsSettingsModel(detect: { _, _ in .success(url) }, probe: { _ in .success("9.9.9") })
        await m.redetect(overrides: [:])
        await m.test(.claude)
        await m.test(.git)
        #expect(m.rows.first { $0.tool == .claude }?.versionWarning != nil)
        #expect(m.rows.first { $0.tool == .git }?.versionWarning == nil)
    }

    @Test func startingPhaseBecomesReadyOnlyAfterWorkFinishes() async {
        let progress = StartupProgress()
        #expect(progress.phase == .starting)
        let value = await progress.run { 42 }
        #expect(value == 42)
        #expect(progress.phase == .ready)
    }
}
