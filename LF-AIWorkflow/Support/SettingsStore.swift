//
//  SettingsStore.swift
//  LF-AIWorkflow
//

import Foundation
import Observation
import SwiftUI

nonisolated enum ArtStyle: String, Sendable, CaseIterable {
    case classic, popArt
}

nonisolated enum AppearanceChoice: String, Sendable, CaseIterable {
    case system, light, dark

    /// Complexity: O(1) time, O(1) space
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A global hotkey as Carbon sees it (virtual key code plus modifier mask). Chosen from presets in Settings.
nonisolated struct HotkeySpec: Codable, Sendable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Space with Option and Command (Carbon `kVK_Space`, `optionKey | cmdKey`).
    static let `default` = HotkeySpec(keyCode: 49, modifiers: 2304)
}

nonisolated enum EditorChoice: String, Sendable, CaseIterable {
    case systemDefault, xcode, vscode
}

/// Immutable copy of the settings, taken when a task starts. Running tasks keep the copy they were started with.
nonisolated struct SettingsSnapshot: Sendable, Equatable {
    let artStyle: ArtStyle
    let appearance: AppearanceChoice
    let peekEnabled: Bool
    let hotkey: HotkeySpec
    let editorChoice: EditorChoice
    let stageModels: [WorkflowStage: String]
    let stageMaxTurns: [WorkflowStage: Int]
    let taskBudget: Int
    let dayBudget: Int
    let promptCaps: [WorkflowStage: Int]
    let toolPaths: [Tool: String]
}

/// User settings shared by the notch panel and the Settings window. Main-actor; values cross to actors only as a `SettingsSnapshot`.
/// Every write persists immediately. Unknown or wrongly typed stored values fall back to the defaults on load.
@Observable
final class SettingsStore {
    nonisolated enum Keys {
        static let artStyle = "settings.artStyle"
        static let appearance = "settings.appearance"
        static let peekEnabled = "settings.peekEnabled"
        static let hotkey = "settings.hotkey"
        static let editorChoice = "settings.editorChoice"
        static let stageModels = "settings.stageModels"
        static let stageMaxTurns = "settings.stageMaxTurns"
        static let taskBudget = "settings.taskBudget"
        static let dayBudget = "settings.dayBudget"
        static let promptCaps = "settings.promptCaps"
        static let toolPaths = "settings.toolPaths"
    }

    /// Per-task token cap default: the same value `TokenBudget.default` uses.
    nonisolated static let defaultTaskBudget = TokenBudget.default.perTaskMaxTokens

    var artStyle: ArtStyle = .classic {
        didSet { defaults.set(artStyle.rawValue, forKey: Keys.artStyle) }
    }
    var appearance: AppearanceChoice = .system {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var peekEnabled: Bool = true {
        didSet { defaults.set(peekEnabled, forKey: Keys.peekEnabled) }
    }
    var hotkey: HotkeySpec = .default {
        didSet {
            // Encoding a two-integer struct cannot fail, so the optional is never nil in practice.
            if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: Keys.hotkey) }
        }
    }
    var editorChoice: EditorChoice = .systemDefault {
        didSet { defaults.set(editorChoice.rawValue, forKey: Keys.editorChoice) }
    }
    /// Model name per stage. A missing stage means the stage's table default. Only `KnownModels` names are kept.
    var stageModels: [WorkflowStage: String] = [:] {
        didSet {
            // Re-assigning inside didSet re-enters the observer, so normalize only when the value actually changes.
            let models = Self.sanitizedModels(stageModels)
            if models != stageModels { stageModels = models; return }
            defaults.set(Self.rawKeyed(stageModels), forKey: Keys.stageModels)
        }
    }
    /// Turn cap per stage, clamped to `SettingsLimits.maxTurns`. A missing stage means the engine default.
    var stageMaxTurns: [WorkflowStage: Int] = [:] {
        didSet {
            let turns = stageMaxTurns.mapValues { SettingsValidation.clamp($0, to: SettingsLimits.maxTurns) }
            if turns != stageMaxTurns { stageMaxTurns = turns; return }
            defaults.set(Self.rawKeyed(stageMaxTurns), forKey: Keys.stageMaxTurns)
        }
    }
    /// Tokens per task. Clamped to >= 0.
    var taskBudget: Int = defaultTaskBudget {
        didSet {
            let budget = SettingsValidation.clamp(taskBudget, to: SettingsLimits.taskTokens)
            if budget != taskBudget { taskBudget = budget; return }
            defaults.set(taskBudget, forKey: Keys.taskBudget)
        }
    }
    /// Tokens per day. 0 means no daily cap. Clamped to >= 0.
    var dayBudget: Int = 0 {
        didSet {
            let budget = SettingsValidation.clamp(dayBudget, to: SettingsLimits.dayTokens)
            if budget != dayBudget { dayBudget = budget; return }
            defaults.set(dayBudget, forKey: Keys.dayBudget)
        }
    }
    /// Prompt token cap per stage, clamped to `SettingsLimits.promptTokens`. Starts at the `TokenBudget` defaults.
    var promptCaps: [WorkflowStage: Int] = TokenBudget.default.promptMaxTokens {
        didSet {
            let caps = promptCaps.mapValues { SettingsValidation.clamp($0, to: SettingsLimits.promptTokens) }
            if caps != promptCaps { promptCaps = caps; return }
            defaults.set(Self.rawKeyed(promptCaps), forKey: Keys.promptCaps)
        }
    }
    /// Plain executable paths typed or picked by the user. Passed as process arguments only, never as shell text.
    var toolPaths: [Tool: String] = [:] {
        didSet {
            let paths = toolPaths.filter { !$0.value.isEmpty }
            if paths != toolPaths { toolPaths = paths; return }
            defaults.set(Self.rawKeyed(toolPaths), forKey: Keys.toolPaths)
        }
    }

    /// Set by the app after each registration attempt; not persisted. False means the system refused the combination.
    var hotkeyRegistered = true

    /// User-facing message when the chosen shortcut could not be registered; nil when it works.
    /// Complexity: O(1) time, O(1) space
    var hotkeyNotice: String? {
        hotkeyRegistered ? nil : "The shortcut \(hotkey.displayString) is already in use by another app. Pick a different one in Settings."
    }

    /// `UserDefaults` is not Sendable, so the suite name is kept and the defaults opened per use.
    private let suiteName: String?

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Loads every key; missing or invalid values use the defaults. Property observers do not run here, so loading never writes.
    /// Complexity: O(n) time, O(n) space (n = stored stage and tool entries)
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
        let stored = defaults
        artStyle = Self.enumValue(stored, Keys.artStyle, fallback: .classic)
        appearance = Self.enumValue(stored, Keys.appearance, fallback: .system)
        peekEnabled = stored.object(forKey: Keys.peekEnabled) as? Bool ?? true
        hotkey = stored.data(forKey: Keys.hotkey)
            .flatMap { try? JSONDecoder().decode(HotkeySpec.self, from: $0) }
            .flatMap { HotkeySpec.presets.contains($0) ? $0 : nil } ?? .default
        editorChoice = Self.enumValue(stored, Keys.editorChoice, fallback: .systemDefault)
        stageModels = Self.sanitizedModels(
            Self.stageKeyed(stored.dictionary(forKey: Keys.stageModels) as? [String: String] ?? [:]))
        stageMaxTurns = Self.stageKeyed(stored.dictionary(forKey: Keys.stageMaxTurns) as? [String: Int] ?? [:])
            .mapValues { SettingsValidation.clamp($0, to: SettingsLimits.maxTurns) }
        taskBudget = SettingsValidation.clamp(
            stored.object(forKey: Keys.taskBudget) as? Int ?? Self.defaultTaskBudget, to: SettingsLimits.taskTokens)
        dayBudget = SettingsValidation.clamp(stored.object(forKey: Keys.dayBudget) as? Int ?? 0, to: SettingsLimits.dayTokens)
        let storedCaps = Self.stageKeyed(stored.dictionary(forKey: Keys.promptCaps) as? [String: Int] ?? [:])
        promptCaps = TokenBudget.default.promptMaxTokens.merging(
            storedCaps.mapValues { SettingsValidation.clamp($0, to: SettingsLimits.promptTokens) }) { _, stored in stored }
        toolPaths = Self.toolKeyed(stored.dictionary(forKey: Keys.toolPaths) as? [String: String] ?? [:])
            .filter { !$0.value.isEmpty }
    }

    /// Complexity: O(1) time, O(1) space
    func snapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            artStyle: artStyle, appearance: appearance, peekEnabled: peekEnabled, hotkey: hotkey,
            editorChoice: editorChoice, stageModels: stageModels, stageMaxTurns: stageMaxTurns,
            taskBudget: taskBudget, dayBudget: dayBudget, promptCaps: promptCaps, toolPaths: toolPaths)
    }

    // MARK: - Decoding helpers

    /// Complexity: O(1) time, O(1) space
    private static func enumValue<T: RawRepresentable & Sendable>(_ defaults: UserDefaults, _ key: String, fallback: T) -> T
    where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    /// Keeps only known stages; unknown raw keys are dropped.
    /// Complexity: O(n) time, O(n) space (n = entries)
    private static func stageKeyed<V>(_ raw: [String: V]) -> [WorkflowStage: V] {
        raw.reduce(into: [:]) { result, entry in
            if let stage = WorkflowStage(rawValue: entry.key) { result[stage] = entry.value }
        }
    }

    /// Keeps only known tools; unknown raw keys are dropped.
    /// Complexity: O(n) time, O(n) space (n = entries)
    private static func toolKeyed<V>(_ raw: [String: V]) -> [Tool: V] {
        raw.reduce(into: [:]) { result, entry in
            if let tool = Tool(rawValue: entry.key) { result[tool] = entry.value }
        }
    }

    /// Trims model names and keeps only `KnownModels` names; anything else never reaches argv.
    /// Complexity: O(n) time, O(n) space (n = stages)
    private static func sanitizedModels(_ models: [WorkflowStage: String]) -> [WorkflowStage: String] {
        models.reduce(into: [:]) { result, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if SettingsValidation.isKnownModel(trimmed) { result[entry.key] = trimmed }
        }
    }

    /// Complexity: O(n) time, O(n) space (n = entries)
    private static func rawKeyed<Key: RawRepresentable, V>(_ dict: [Key: V]) -> [String: V] where Key.RawValue == String {
        Dictionary(uniqueKeysWithValues: dict.map { ($0.key.rawValue, $0.value) })
    }
}
