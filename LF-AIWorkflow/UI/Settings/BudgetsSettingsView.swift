//
//  BudgetsSettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Budgets tab: per-task and daily token limits and the prompt cap per stage. Values apply to tasks started after the change.
struct BudgetsSettingsView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private let dayControl = DayBudgetControl.current
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        Form {
            Section("Tokens") {
                ClampedNumberField(label: "Per task", range: SettingsLimits.taskTokens, value: settings.taskBudget) {
                    settings.taskBudget = $0
                }
                Text("A task pauses when its spend plus the next prompt would pass this limit.")
                    .font(theme.captionFont.font)
                    .foregroundStyle(palette.secondaryText.color)
                ClampedNumberField(
                    label: dayControl.label, range: SettingsLimits.dayTokens, value: settings.dayBudget,
                    isEnabled: dayControl.isEnabled, accessibilityLabel: dayControl.accessibilityLabel
                ) { settings.dayBudget = $0 }
                Text(dayControl.caption)
                    .font(theme.captionFont.font)
                    .foregroundStyle(palette.secondaryText.color)
            }
            Section("Prompt size per stage") {
                ForEach(WorkflowStage.allCases, id: \.self) { stage in
                    ClampedNumberField(
                        label: stage.displayName, range: SettingsLimits.promptTokens,
                        value: settings.promptCaps[stage] ?? TokenBudget.default.promptCap(for: stage)
                    ) { settings.promptCaps[stage] = $0 }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-budgets")
    BudgetsSettingsView(settings: settings)
        .frame(width: 540, height: 620)
}
