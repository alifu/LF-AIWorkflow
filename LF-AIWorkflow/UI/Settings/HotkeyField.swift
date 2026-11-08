//
//  HotkeyField.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Shortcut preset picker. Shows the system's refusal when the chosen combination is taken.
struct HotkeyField: View {
    @Bindable var settings: SettingsStore
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        Picker("Shortcut", selection: $settings.hotkey) {
            ForEach(HotkeySpec.presets, id: \.self) { preset in
                Text(preset.displayString).tag(preset)
            }
        }
        .accessibilityLabel("Global shortcut")
        .accessibilityValue(settings.hotkey.displayString)
        .accessibilityHint("Opens the notch panel from anywhere")
        if let notice = settings.hotkeyNotice {
            Label(notice, systemImage: "exclamationmark.triangle")
                .font(theme.captionFont.font)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("Shortcut problem: \(notice)")
        }
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-hotkey")
    Form { HotkeyField(settings: settings) }
        .padding()
        .frame(width: 360)
}
