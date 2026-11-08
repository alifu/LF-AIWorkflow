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
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    init(task: WorkflowTask, decider: any TaskDeciding, hover: HoverController?, loader: any PlanLoading = FilePlanLoader(),
         onClose: @escaping () -> Void) {
        _model = State(initialValue: PlanApprovalViewModel(task: task, loader: loader, opener: EditorOpener(), decider: decider))
        self.hover = hover
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approve plan: \(model.title)").font(theme.titleFont.font).lineLimit(2)
            if let path = model.planPath {
                Text(path).font(theme.monoFont.font).foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1).truncationMode(.middle)
            }
            summary
            if let error = model.loadError ?? model.openError {
                Text(error).font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
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
        .themedSurface(.sheet)
        .overlay(RoundedRectangle(cornerRadius: theme.sheetCornerRadius, style: .continuous).strokeBorder(palette.outline.color))
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
                .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
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
