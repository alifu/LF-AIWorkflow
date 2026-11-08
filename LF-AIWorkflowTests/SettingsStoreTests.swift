//
//  SettingsStoreTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import SwiftUI
import Testing
@testable import LF_AIWorkflow

@MainActor
struct SettingsStoreTests {
    /// Fresh UserDefaults suite per test so nothing leaks between cases or into the real app defaults.
    private func makeSuite() -> String { "lf-settings-test-\(UUID().uuidString)" }

    private func rawDefaults(_ suite: String) -> UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func emptySuiteYieldsDocumentedDefaults() {
        let store = SettingsStore(suiteName: makeSuite())

        #expect(store.artStyle == .classic)
        #expect(store.appearance == .system)
        #expect(store.peekEnabled)
        #expect(store.hotkey == HotkeySpec.default)
        #expect(store.editorChoice == .systemDefault)
        #expect(store.stageModels.isEmpty)
        #expect(store.stageMaxTurns.isEmpty)
        #expect(store.taskBudget == 150_000)
        #expect(store.dayBudget == 0)
        #expect(store.toolPaths.isEmpty)
    }

    @Test func defaultHotkeyIsOptionCommandSpace() {
        // Carbon: kVK_Space = 49, optionKey | cmdKey = 0x800 | 0x100 = 2304
        #expect(HotkeySpec.default == HotkeySpec(keyCode: 49, modifiers: 2304))
    }

    @Test func artStyleRoundTrips() {
        let suite = makeSuite()
        let store = SettingsStore(suiteName: suite)
        store.artStyle = .popArt
        #expect(SettingsStore(suiteName: suite).artStyle == .popArt)
    }

    @Test func appearanceRoundTrips() {
        let suite = makeSuite()
        SettingsStore(suiteName: suite).appearance = .dark
        #expect(SettingsStore(suiteName: suite).appearance == .dark)
    }

    @Test func peekRoundTrips() {
        let suite = makeSuite()
        SettingsStore(suiteName: suite).peekEnabled = false
        #expect(SettingsStore(suiteName: suite).peekEnabled == false)
    }

    @Test func hotkeyRoundTrips() {
        let suite = makeSuite()
        let chosen = HotkeySpec.optionCommandN
        SettingsStore(suiteName: suite).hotkey = chosen
        #expect(SettingsStore(suiteName: suite).hotkey == chosen)
    }

    @Test func editorRoundTrips() {
        let suite = makeSuite()
        SettingsStore(suiteName: suite).editorChoice = .vscode
        #expect(SettingsStore(suiteName: suite).editorChoice == .vscode)
    }

    @Test func stageModelsRoundTrip() {
        let suite = makeSuite()
        SettingsStore(suiteName: suite).stageModels = [.plan: "opus", .review: "haiku"]
        #expect(SettingsStore(suiteName: suite).stageModels == [.plan: "opus", .review: "haiku"])
    }

    @Test func stageMaxTurnsRoundTrip() {
        let suite = makeSuite()
        SettingsStore(suiteName: suite).stageMaxTurns = [.code: 40]
        #expect(SettingsStore(suiteName: suite).stageMaxTurns == [.code: 40])
    }

    @Test func budgetsRoundTrip() {
        let suite = makeSuite()
        let store = SettingsStore(suiteName: suite)
        store.taskBudget = 250_000
        store.dayBudget = 3_000_000
        let reloaded = SettingsStore(suiteName: suite)
        #expect(reloaded.taskBudget == 250_000)
        #expect(reloaded.dayBudget == 3_000_000)
    }

    @Test func toolPathsAreStoredVerbatimAsPlainStrings() {
        let suite = makeSuite()
        let path = "/opt/my tools/claude \"beta\"; rm -rf ~"
        SettingsStore(suiteName: suite).toolPaths = [.claude: path]
        #expect(SettingsStore(suiteName: suite).toolPaths == [.claude: path])
    }

    @Test func unknownArtStyleFallsBackToDefault() {
        let suite = makeSuite()
        rawDefaults(suite).set("neon", forKey: SettingsStore.Keys.artStyle)
        #expect(SettingsStore(suiteName: suite).artStyle == .classic)
    }

    @Test func unknownAppearanceFallsBackToDefault() {
        let suite = makeSuite()
        rawDefaults(suite).set(42, forKey: SettingsStore.Keys.appearance)
        #expect(SettingsStore(suiteName: suite).appearance == .system)
    }

    @Test func corruptHotkeyDataFallsBackToDefault() {
        let suite = makeSuite()
        rawDefaults(suite).set(Data([0x00, 0x01, 0xFF]), forKey: SettingsStore.Keys.hotkey)
        #expect(SettingsStore(suiteName: suite).hotkey == HotkeySpec.default)
    }

    @Test func validButNonPresetHotkeyFallsBackToDefaultOnLoad() throws {
        let suite = makeSuite()
        let custom = HotkeySpec(keyCode: 36, modifiers: 256)
        #expect(custom.validate() == .valid)
        rawDefaults(suite).set(try JSONEncoder().encode(custom), forKey: SettingsStore.Keys.hotkey)
        #expect(SettingsStore(suiteName: suite).hotkey == HotkeySpec.default)
    }

    @Test func wrongTypeBudgetFallsBackToDefault() {
        let suite = makeSuite()
        rawDefaults(suite).set("lots", forKey: SettingsStore.Keys.taskBudget)
        #expect(SettingsStore(suiteName: suite).taskBudget == 150_000)
    }

    @Test func maxTurnsAboveRangeAreClampedToUpperBound() {
        let suite = makeSuite()
        rawDefaults(suite).set([WorkflowStage.code.rawValue: 500], forKey: SettingsStore.Keys.stageMaxTurns)
        #expect(SettingsStore(suiteName: suite).stageMaxTurns == [.code: 200])
    }

    @Test func maxTurnsBelowRangeAreClampedToLowerBound() {
        let suite = makeSuite()
        rawDefaults(suite).set([WorkflowStage.fix.rawValue: 0], forKey: SettingsStore.Keys.stageMaxTurns)
        #expect(SettingsStore(suiteName: suite).stageMaxTurns == [.fix: 1])
    }

    @Test func negativeBudgetIsClampedToZero() {
        let suite = makeSuite()
        rawDefaults(suite).set(-5, forKey: SettingsStore.Keys.dayBudget)
        #expect(SettingsStore(suiteName: suite).dayBudget == 0)
    }

    @Test func unknownStageKeysAndBlankModelsAreDropped() {
        let suite = makeSuite()
        rawDefaults(suite).set(
            [WorkflowStage.plan.rawValue: "opus", "bogus": "x", WorkflowStage.fix.rawValue: "   "],
            forKey: SettingsStore.Keys.stageModels)
        #expect(SettingsStore(suiteName: suite).stageModels == [.plan: "opus"])
    }

    @Test func appearanceMapsToColorScheme() {
        #expect(AppearanceChoice.system.colorScheme == nil)
        #expect(AppearanceChoice.light.colorScheme == .light)
        #expect(AppearanceChoice.dark.colorScheme == .dark)
    }

    @Test func snapshotKeepsTheSettingsItWasTakenWith() {
        let store = SettingsStore(suiteName: makeSuite())
        let before = store.snapshot()

        store.artStyle = .popArt
        store.taskBudget = 1

        #expect(before.artStyle == .classic)
        #expect(before.taskBudget == 150_000)
        #expect(store.snapshot().artStyle == .popArt)
        #expect(store.snapshot().taskBudget == 1)
    }
}
