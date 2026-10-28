//
//  SettingsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The Settings window (⌘,). Tabs: General (includes the display override), Tools, Stages, Budgets.
struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ToolsSettingsView(settings: settings)
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            StagesSettingsView(settings: settings)
                .tabItem { Label("Stages", systemImage: "list.bullet.rectangle") }
            BudgetsSettingsView(settings: settings)
                .tabItem { Label("Budgets", systemImage: "gauge") }
        }
        .frame(width: 540, height: 620)
    }
}

#Preview {
    @Previewable @State var settings = SettingsStore(suiteName: "preview-settings")
    SettingsView(settings: settings)
}
