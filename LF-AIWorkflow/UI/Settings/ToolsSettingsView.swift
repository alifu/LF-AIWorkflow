//
//  ToolsSettingsView.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// Tools tab: the detected path of each CLI, an optional override picked with a file panel, and a `--version` test.
/// Overrides are validated (absolute, existing, executable regular file) and used only as the executable of a process.
struct ToolsSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var model = ToolsSettingsModel()
    @State private var pathMessages: [Tool: String] = [:]
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        Form {
            ForEach(model.rows) { row in
                Section(row.tool.displayName) {
                    statusLine(row)
                    if let override = settings.toolPaths[row.tool] {
                        LabeledContent("Override") {
                            Text(override)
                                .font(theme.monoFont.font)
                                .foregroundStyle(palette.secondaryText.color)
                                .textSelection(.enabled)
                        }
                    }
                    controls(for: row)
                    versionLine(row)
                    if let message = pathMessages[row.tool] {
                        Text(message)
                            .font(theme.captionFont.font)
                            .foregroundStyle(palette.primaryText.color)
                            .accessibilityLabel("\(row.tool.displayName) path: \(message)")
                    }
                }
            }
            Section {
                Button("Re-detect") { redetect() }
                    .accessibilityHint("Searches again for every tool using the current overrides")
                Text("Path changes take effect after the app restarts.")
                    .font(theme.captionFont.font)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .formStyle(.grouped)
        .task { await model.redetect(overrides: settings.toolPaths) }
    }

    @ViewBuilder
    private func statusLine(_ row: ToolsSettingsModel.Row) -> some View {
        if let path = row.path {
            Label(path, systemImage: "checkmark.circle")
                .font(theme.bodyFont.font)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("\(row.tool.displayName) found at \(path)")
        } else {
            Label(row.problem ?? "Not found", systemImage: "xmark.circle")
                .font(theme.bodyFont.font)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("\(row.tool.displayName) not found")
        }
    }

    private func controls(for row: ToolsSettingsModel.Row) -> some View {
        HStack {
            Button("Choose…") { choose(row.tool) }
                .accessibilityLabel("Choose \(row.tool.displayName) path")
            Button("Use detected") { useDetected(row.tool) }
                .disabled(settings.toolPaths[row.tool] == nil)
                .accessibilityLabel("Use detected \(row.tool.displayName) path")
            Button("Test") { Task { await model.test(row.tool) } }
                .disabled(row.path == nil)
                .accessibilityLabel("Test \(row.tool.displayName), run --version")
        }
    }

    @ViewBuilder
    private func versionLine(_ row: ToolsSettingsModel.Row) -> some View {
        switch row.version {
        case .unchecked:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
                .accessibilityLabel("Checking \(row.tool.displayName) version")
        case .found(let line):
            Text(line)
                .font(theme.captionFont.font)
                .foregroundStyle(palette.secondaryText.color)
                .accessibilityLabel("Version: \(line)")
        case .failed(let reason):
            Text(reason)
                .font(theme.captionFont.font)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("Version check failed: \(reason)")
        }
    }

    /// Opens a file panel limited to one file. The choice is validated before it is stored.
    private func choose(_ tool: Tool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.message = "Choose the \(tool.displayName) executable"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch ToolPathValidator.validate(url.path, kind: ToolPathValidator.kind(atPath:)) {
        case .success(let path):
            pathMessages[tool] = nil
            settings.toolPaths[tool] = path
            redetect()
        case .failure(let error):
            pathMessages[tool] = error.message
        }
    }

    private func useDetected(_ tool: Tool) {
        pathMessages[tool] = nil
        settings.toolPaths[tool] = nil
        redetect()
    }

    private func redetect() {
        Task { await model.redetect(overrides: settings.toolPaths) }
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-tools")
    ToolsSettingsView(settings: settings)
        .frame(width: 540, height: 620)
}
