//
//  GeneralSettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// General tab: look (art style with live preview, appearance), shortcut, peek and the display override.
struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Look") {
                ArtStylePicker(selection: $settings.artStyle)
                ArtStylePreview()
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(AppearanceChoice.system)
                    Text("Light").tag(AppearanceChoice.light)
                    Text("Dark").tag(AppearanceChoice.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance")
                .accessibilityValue(settings.appearance.rawValue)
            }
            Section("Behavior") {
                HotkeyField(settings: settings)
                Toggle("Show peek messages", isOn: $settings.peekEnabled)
                    .accessibilityHint("Shows a short message from the mascot when a task needs you")
            }
            DisplaySettingsView()
        }
        .formStyle(.grouped)
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-general")
    GeneralSettingsView(settings: settings)
        .frame(width: 520, height: 640)
}
