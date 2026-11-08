//
//  ThemedRoot.swift
//  LF-AIWorkflow
//

import AppKit
import Observation
import SwiftUI

extension AppearanceChoice {
    /// The AppKit appearance to force; nil follows the system.
    /// Complexity: O(1) time, O(1) space
    nonisolated var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

extension SettingsStore {
    /// The theme for the chosen art style.
    /// Complexity: O(1) time, O(1) space
    var theme: AppTheme {
        switch artStyle {
        case .classic: .classic
        case .popArt: .popArt
        }
    }
}

/// `preferredColorScheme` does not reach an `NSHostingView` inside a borderless panel, so the appearance is also set on AppKit objects.
enum AppearanceApplier {
    /// Complexity: O(1) time, O(1) space
    static func apply(_ choice: AppearanceChoice, to target: any NSAppearanceCustomization) {
        target.appearance = choice.nsAppearanceName.flatMap(NSAppearance.init(named:))
    }
}

/// Keeps AppKit objects (panel, hosting view) on the stored appearance choice, re-arming after every change.
/// Complexity: O(t) time per change, O(t) space (t = targets)
final class AppearanceObserver {
    private let settings: SettingsStore
    private let targets: [any NSAppearanceCustomization]

    init(settings: SettingsStore, targets: [any NSAppearanceCustomization]) {
        self.settings = settings
        self.targets = targets
        apply()
    }

    private func apply() {
        let choice = withObservationTracking {
            settings.appearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.apply() }
        }
        for target in targets { AppearanceApplier.apply(choice, to: target) }
    }
}

/// Injects the theme, the appearance override and the shared settings store into one view tree.
/// Used for BOTH the panel's hosting view and the Settings scene, which are separate trees sharing one `SettingsStore`.
struct ThemedRoot<Content: View>: View {
    let settings: SettingsStore
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.appTheme, settings.theme)
            .environment(settings)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}
