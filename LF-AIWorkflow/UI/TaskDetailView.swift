//
//  TaskDetailView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// One task in detail: stage strip, mascot, plan/review slots, its activity log and worktree footer.
struct TaskDetailView: View {
    let row: TaskRowModel?
    let model: any WorkflowControlling
    let router: PanelRouter
    var hover: HoverController?
    @State private var approvalDismissed = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { router.closeDetail() } label: { Label("Back", systemImage: "chevron.left") }
                    .controlSize(.small)
                    .accessibilityLabel("Back to task list")
                    .keyboardShortcut(.cancelAction)
                Text(row?.title ?? "Task").font(theme.titleFont.font).lineLimit(1)
                Spacer()
                if let row, row.actions.contains(.cancel) {
                    Button("Cancel task", role: .destructive) { Task { await model.cancel(row.id) } }
                        .controlSize(.small)
                }
            }
            if let row {
                HStack(alignment: .top, spacing: 12) {
                    MascotView(pose: pose(row), size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        StageChipStrip(chips: row.chips)
                        TaskStatusLine(text: row.statusLine, needsAttention: row.needsAttention, font: theme.bodyLargeFont)
                        detailActions(row)
                    }
                }
                if let task = model.task(row.id) {
                    if row.actions.contains(.viewReview) {
                        ReviewView(task: task, sendToFix: { findings in Task { await model.sendToFix(task.id, findings: findings) } }, onDone: { router.closeDetail() }).id(task.reviewFile)
                    }
                    if row.actions.contains(.viewPlan) { PlanView(task: task).id(row.state) }
                }
                TaskLogPane(model: model, taskID: row.id, caption: "Activity · read-only")
                footer(row)
            } else {
                Text("This task is no longer listed.").foregroundStyle(palette.secondaryText.color)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay { approvalSheet }
        .onChange(of: row?.id) { _, _ in approvalDismissed = false }
    }

    /// The in-panel approval sheet, shown while the plan waits for a decision.
    @ViewBuilder private var approvalSheet: some View {
        if let row, row.actions.contains(.approve), !approvalDismissed, let task = model.task(row.id) {
            ZStack {
                palette.scrim.color
                PlanApprovalView(task: task, decider: model, hover: hover, onClose: { approvalDismissed = true })
            }
            .transition(.opacity)
        }
    }

    private func pose(_ row: TaskRowModel) -> MascotPose {
        switch row.state {
        case .done: .done
        case .failed: .error
        case .awaitingApproval, .awaitingInput: .attention
        case .cancelled, .queued: .idle
        default: .typing
        }
    }

    private func detailActions(_ row: TaskRowModel) -> some View {
        HStack(spacing: 6) {
            if row.actions.contains(.approve) {
                Button("Review plan") { approvalDismissed = false }
                    .accessibilityHint("Opens the plan approval sheet")
                Button("Approve") { Task { _ = await model.approve(row.id) } }.buttonStyle(.borderedProminent)
            }
            if row.actions.contains(.resume) { Button(row.resumeLabel) { Task { await model.resume(row.id, raising: row.resumeRaiseTokens) } } }
            if row.actions.contains(.skipTests) { Button("Skip tests") { Task { await model.skipTests(row.id) } } }
            if row.actions.contains(.openWorktree) { Button("Open worktree") { model.openWorktree(row.id) } }
        }
        .controlSize(.small)
    }

    @ViewBuilder private func footer(_ row: TaskRowModel) -> some View {
        if let branch = row.branch, let path = row.worktreePath {
            Text("\(branch) · \(path)")
                .font(theme.monoFont.font).foregroundStyle(palette.secondaryText.color)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

#if DEBUG
#Preview {
    let model = PreviewModel()
    TaskDetailView(row: model.rows.first, model: model, router: PanelRouter())
        .frame(width: 560, height: 360).background(.black).environment(\.colorScheme, .dark)
}
#endif
