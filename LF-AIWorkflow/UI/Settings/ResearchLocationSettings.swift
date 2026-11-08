//
//  ResearchLocationSettings.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Inbox shortcut picker and research folder field. Both take effect as validated values only.
struct ResearchLocationSettings: View {
    @Bindable var settings: SettingsStore
    @State private var rootText = ""
    @State private var rootError: String?

    var body: some View {
        Section("Research") {
            Picker("Inbox shortcut", selection: $settings.inboxHotkey) {
                ForEach(HotkeySpec.inboxChoices(excluding: settings.hotkey), id: \.self) { spec in
                    Text(spec.displayString).tag(spec)
                }
            }
            .accessibilityLabel("Inbox shortcut")
            .accessibilityHint("Saves the current Safari tab to the research inbox")
            TextField("Research folder", text: $rootText, prompt: Text(SettingsStore.defaultResearchRoot().path))
                .onSubmit(commit)
                .accessibilityLabel("Research folder")
                .accessibilityHint("Absolute path. Leave empty for the default. Applies after restart")
            if let rootError {
                Label(rootError, systemImage: "exclamationmark.triangle")
                    .accessibilityLabel("Research folder problem: \(rootError)")
            }
        }
        .onAppear { rootText = settings.researchRootPath }
    }

    private func commit() {
        switch ResearchRootValidator.validate(rootText) {
        case .success(let path):
            rootError = nil
            rootText = path
            settings.researchRootPath = path
        case .failure(let error):
            rootError = error.message
        }
    }
}
