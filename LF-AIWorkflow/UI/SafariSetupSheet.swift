//
//  SafariSetupSheet.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// Explains which Safari permission is missing and how to fix it.
struct SafariSetupSheet: View {
    let guide: SafariSetupGuide
    let onClose: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.title).font(theme.titleFont.font)
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)").font(theme.bodyLargeFont.font)
            }
            Text(guide.fallback).font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            HStack {
                if guide.showsOpenSettings {
                    Button("Open System Settings") { NSWorkspace.shared.open(SafariSetupGuide.settingsURL) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens the Automation privacy pane")
                }
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420)
        .themedSurface(.sheet)
    }
}
