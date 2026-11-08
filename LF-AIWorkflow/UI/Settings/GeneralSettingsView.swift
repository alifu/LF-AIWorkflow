//
//  GeneralSettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// General tab: look (art style with live preview, appearance), shortcut, peek and the display override.
struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var loginItem = LaunchAtLoginModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    // swiftlint:disable:next force_unwrapping
    private static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension")!

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
                Toggle("Show alerts", isOn: $settings.alertsEnabled)
                    .accessibilityHint("Allows alerts when a task needs you")
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                if let message = loginItem.errorMessage {
                    Text(message)
                        .font(theme.captionFont.font)
                        .foregroundStyle(theme.palette(for: scheme).secondaryText.color)
                }
                Picker("Open files with", selection: $settings.editorChoice) {
                    ForEach(EditorChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityHint("Editor used for findings and plans; Xcode and VS Code also jump to the line")
                LabeledContent("Reduce animations") {
                    VStack(alignment: .trailing) {
                        Text(reduceMotion ? "On (system setting)" : "Off (system setting)")
                        Link("Accessibility settings", destination: Self.accessibilityURL)
                    }
                }
            }
            ResearchLocationSettings(settings: settings)
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
