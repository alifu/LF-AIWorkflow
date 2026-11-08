//
//  StartingView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Shown in the collapsed panel while services start (the login-shell PATH can take up to 5 s).
struct StartingView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    let progress: StartupProgress

    var body: some View {
        if progress.phase == .failed { failedBody } else { startingBody }
    }

    private var failedBody: some View {
        HStack(spacing: 8) {
            Text("Startup is taking too long.")
                .font(theme.captionFont.font)
                .foregroundStyle(palette.secondaryText.color)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LF-AIWorkflow failed to start. Quit and relaunch.")
    }

    private var startingBody: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Starting…")
                .font(theme.captionFont.font)
                .foregroundStyle(palette.secondaryText.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LF-AIWorkflow is starting")
    }
}
