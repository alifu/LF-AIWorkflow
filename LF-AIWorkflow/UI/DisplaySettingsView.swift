//
//  DisplaySettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Debug aid: simulate a notch / no notch on the current display. The rest of Settings is Phase 6.
struct DisplaySettingsView: View {
    @AppStorage(DisplayOverride.defaultsKey) private var override = DisplayOverride.auto.rawValue
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        Form {
            Picker("Notch", selection: $override) {
                Text("Auto").tag(DisplayOverride.auto.rawValue)
                Text("Notch").tag(DisplayOverride.notch.rawValue)
                Text("No notch").tag(DisplayOverride.noNotch.rawValue)
            }
            .pickerStyle(.radioGroup)
            Text("Launching with -LFSimulateNotch YES or NO overrides this setting.")
                .font(theme.captionFont.font)
                .foregroundStyle(palette.secondaryText.color)
        }
        .padding(20)
        .frame(width: 360)
    }
}

#Preview {
    DisplaySettingsView()
}
