//
//  StagesSettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Stages tab: model and turn cap per stage. Allowed tools are shown for reference and cannot be edited here.
struct StagesSettingsView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    /// The table defaults the stored overrides fall back to.
    private static let table = StagePolicy.defaults(testCommand: nil)

    var body: some View {
        Form {
            ForEach(WorkflowStage.allCases, id: \.self) { stage in
                let config = Self.table.config(for: stage)
                Section(stage.displayName) {
                    Picker("Model", selection: modelBinding(for: stage)) {
                        ForEach(KnownModels.all, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .accessibilityLabel("\(stage.displayName) model")
                    ClampedNumberField(
                        label: "Max turns", range: SettingsLimits.maxTurns,
                        value: settings.stageMaxTurns[stage] ?? config.maxTurns
                    ) { settings.stageMaxTurns[stage] = $0 }
                    LabeledContent("Allowed tools") {
                        Text(config.allowedTools.joined(separator: ", "))
                            .font(theme.captionFont.font)
                            .foregroundStyle(palette.secondaryText.color)
                            .textSelection(.enabled)
                    }
                    .accessibilityLabel("\(stage.displayName) allowed tools, read only")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Complexity: O(1) time, O(1) space
    private func modelBinding(for stage: WorkflowStage) -> Binding<String> {
        Binding(
            get: { settings.stageModels[stage] ?? Self.table.config(for: stage).model },
            set: { settings.stageModels[stage] = $0 })
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-stages")
    StagesSettingsView(settings: settings)
        .frame(width: 540, height: 620)
}
