//
//  ExpandedView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The open panel: header (mascot, tabs, count, pin, settings), tab content, footer.
struct ExpandedView: View {
    let model: any WorkflowControlling
    let hover: HoverController
    let router: PanelRouter
    /// Space the notch (or menu bar) takes at the top of the panel.
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.1))
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(.white.opacity(0.1))
            footer
        }
        .padding(.top, topInset)
        .background(NotchShape(bottomRadius: 24).fill(.black))
        .clipShape(NotchShape(bottomRadius: 24))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            MascotPlaceholder(pose: MascotPose.pose(for: model.summary), size: 24)
            Text("LF-AIWorkflow").font(.system(size: 13, weight: .semibold))
            Picker("View", selection: Bindable(router).tab) {
                ForEach(ExpandedTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .accessibilityLabel("Panel view")
            Spacer()
            Text("\(model.summary.activeCount) active")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle(isOn: pinBinding) { Image(systemName: hover.state == .pinned ? "pin.fill" : "pin") }
                .toggleStyle(.button)
                .controlSize(.small)
                .accessibilityLabel("Pin panel open")
            SettingsLink { Image(systemName: "gearshape") }
                .controlSize(.small)
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        switch router.tab {
        case .tasks:
            if let id = router.detailTaskID {
                TaskDetailView(row: model.rows.first { $0.id == id }, model: model, router: router, hover: hover)
            } else {
                TaskListView(model: model, router: router)
            }
        case .new:
            PromptComposer(model: model, hover: hover, router: router)
        case .terminal:
            TerminalTabHost(model: model, router: router)
        }
    }

    private var footer: some View {
        HStack {
            if let error = model.lastError {
                Button { model.clearError() } label: {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Dismisses the message")
            } else {
                Text("Today: \(TaskFormat.tokens(model.todayTokens)) tokens")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear done") { model.clearDone() }
                .controlSize(.small)
                .accessibilityHint("Hides finished tasks from the list")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var pinBinding: Binding<Bool> {
        Binding(get: { hover.state == .pinned }, set: { hover.setPinned($0) })
    }
}

#if DEBUG
#Preview("Tasks") {
    ExpandedView(model: PreviewModel(), hover: HoverController(), router: PanelRouter(), topInset: 32)
        .frame(width: 560, height: 400)
}

#Preview("Terminal") {
    let router = PanelRouter()
    router.tab = .terminal
    return ExpandedView(model: PreviewModel(), hover: HoverController(), router: router, topInset: 0)
        .frame(width: 560, height: 400)
}
#endif
