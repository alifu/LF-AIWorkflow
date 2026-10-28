//
//  PlanView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Read-only plan at any status. Hidden when the task has no plan file (research tasks, tasks started at Code).
struct PlanView: View {
    @State private var model: PlanViewModel
    @State private var expanded = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    init(task: WorkflowTask, loader: any PlanLoading = FilePlanLoader()) {
        _model = State(initialValue: PlanViewModel(task: task, loader: loader, opener: EditorOpener(), pasteboard: SystemPasteboard()))
    }

    var body: some View {
        if model.isVisible {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Plan").font(theme.subheadingFont.font)
                    badge
                    Spacer()
                    Button("Open in editor") { model.openInEditor() }
                        .accessibilityHint("Opens the plan file in your default editor")
                    Button(model.didCopy ? "Copied" : "Copy path") { model.copyPath() }
                        .accessibilityLabel("Copy plan path")
                    Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                        .accessibilityLabel(expanded ? "Hide plan steps" : "Show plan steps")
                }
                .controlSize(.small)
                Text(model.pathText).font(theme.monoFont.font).foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1).truncationMode(.middle)
                if let error = model.loadError ?? model.openError {
                    Text(error).font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
                }
                if expanded, let document = model.document { PlanStepsView(steps: document.steps) }
            }
            .padding(10)
            .themedSurface(.row)
            .accessibilityElement(children: .contain)
            .task { await model.load() }
        }
    }

    private var badgeFill: Color {
        let tint = model.badge == .approved ? palette.success : palette.warning
        return tint.fading(theme.pillTintOpacity).color
    }

    private var badge: some View {
        Text(model.badge.text)
            .font(theme.chipFont.weighted(.semibold).font)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(badgeFill))
            .accessibilityLabel(model.badge.accessibilityText)
    }
}

#if DEBUG
#Preview("Approved") {
    PlanView(task: PreviewFixtures.sampleTasks[3], loader: PreviewFixtures.planLoader)
        .padding().frame(width: 520).background(.black).environment(\.colorScheme, .dark)
}

#Preview("Waiting") {
    PlanView(task: PreviewFixtures.sampleTasks[0], loader: PreviewFixtures.planLoader)
        .padding().frame(width: 520).background(.black).environment(\.colorScheme, .dark)
}
#endif
