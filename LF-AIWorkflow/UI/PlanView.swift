//
//  PlanView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Read-only plan at any status. Hidden when the task has no plan file (research tasks, tasks started at Code).
struct PlanView: View {
    @State private var model: PlanViewModel
    @State private var expanded = false

    init(task: WorkflowTask, loader: any PlanLoading = FilePlanLoader()) {
        _model = State(initialValue: PlanViewModel(task: task, loader: loader, opener: EditorOpener(), pasteboard: SystemPasteboard()))
    }

    var body: some View {
        if model.isVisible {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Plan").font(.system(size: 12, weight: .semibold))
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
                Text(model.pathText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let error = model.loadError ?? model.openError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                }
                if expanded, let document = model.document { PlanStepsView(steps: document.steps) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
            .accessibilityElement(children: .contain)
            .task { await model.load() }
        }
    }

    private var badge: some View {
        Text(model.badge.text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(model.badge == .approved ? Color.green.opacity(0.25) : Color.orange.opacity(0.25)))
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
