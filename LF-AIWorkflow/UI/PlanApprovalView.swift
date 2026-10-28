//
//  PlanApprovalView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// In-panel approval sheet (the panel is non-activating, so no system sheet): plan summary, Open in editor, Cancel, Approve.
struct PlanApprovalView: View {
    @State private var model: PlanApprovalViewModel
    let hover: HoverController?
    /// Closes the sheet without deciding.
    let onClose: () -> Void

    init(task: WorkflowTask, decider: any TaskDeciding, hover: HoverController?, loader: any PlanLoading = FilePlanLoader(),
         onClose: @escaping () -> Void) {
        _model = State(initialValue: PlanApprovalViewModel(task: task, loader: loader, opener: EditorOpener(), decider: decider))
        self.hover = hover
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approve plan: \(model.title)").font(.system(size: 14, weight: .semibold)).lineLimit(2)
            if let path = model.planPath {
                Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            summary
            if let error = model.loadError ?? model.openError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let document = model.document { PlanStepsView(steps: document.steps) }
            HStack {
                Button("Open in editor") { model.openInEditor() }
                    .accessibilityHint("Opens the plan file in your default editor")
                Spacer()
                Button("Not now", action: onClose).keyboardShortcut(.cancelAction)
                    .accessibilityHint("Closes this sheet; the task keeps waiting")
                Button("Cancel task", role: .destructive) { Task { await model.cancelTask(); onClose() } }
                    .disabled(!model.canAct)
                Button("Approve") { Task { await model.approve(); onClose() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canAct)
                    .accessibilityHint("Starts the Code stage with this plan")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Plan approval")
        .task { await model.load() }
        .onAppear { hover?.setFocusHold(true) }
        .onDisappear { hover?.setFocusHold(false) }
    }

    @ViewBuilder private var summary: some View {
        if let document = model.document {
            Text("\(document.steps.count) steps · about \(TaskFormat.tokens(document.estimatedTokens)) tokens"
                 + (document.isTruncated ? " · plan shortened for display" : ""))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    let task = PreviewFixtures.sampleTasks[0]
    PlanApprovalView(task: task, decider: PreviewModel(), hover: nil, loader: PreviewFixtures.planLoader, onClose: {})
        .padding().frame(width: 560, height: 360).background(.black).environment(\.colorScheme, .dark)
}
#endif
