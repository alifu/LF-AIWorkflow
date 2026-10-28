//
//  TaskRowView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// One task in the list: title, status, stage strip and the actions its state allows.
struct TaskRowView: View {
    let row: TaskRowModel
    let model: any WorkflowControlling
    let router: PanelRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    ElapsedLabel(row: row)
                    Text(row.tokensText).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                StageChipStrip(chips: row.chips)
                Text(row.statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(row.needsAttention ? Color.orange : .secondary)
                    .lineLimit(2)
                if let progress = row.progress {
                    ProgressView(value: progress).progressViewStyle(.linear).tint(.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel + ". " + row.statusLine)
            actionBar
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(row.needsAttention ? 0.12 : 0.07)))
        .contextMenu { contextMenu }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            if row.actions.contains(.approve) {
                Button("Review plan") { router.show(task: row.id) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Review plan for \(row.title)")
                    .accessibilityHint("Opens the plan approval sheet")
            }
            if row.actions.contains(.resume) {
                Button("Resume") { Task { await model.resume(row.id, raising: 0) } }
            }
            if row.actions.contains(.skipTests) {
                Button("Skip tests") { Task { await model.skipTests(row.id) } }
            }
            Button("Details") { router.show(task: row.id) }
            if row.actions.contains(.cancel) {
                Button("Cancel", role: .destructive) { Task { await model.cancel(row.id) } }
                    .accessibilityLabel("Cancel \(row.title)")
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var contextMenu: some View {
        if row.actions.contains(.cancel) {
            Button("Cancel task", role: .destructive) { Task { await model.cancel(row.id) } }
        }
        if row.actions.contains(.openWorktree) {
            Button("Open worktree in Finder") { model.openWorktree(row.id) }
        }
    }
}

/// Elapsed time; ticks once a second only while the task is running.
struct ElapsedLabel: View {
    let row: TaskRowModel

    var body: some View {
        if row.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(TaskFormat.clock(.seconds(max(0, Int(context.date.timeIntervalSince(row.createdAt))))))
            }
        } else {
            label(row.elapsedText)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    VStack {
        ForEach(PreviewModel().rows) { TaskRowView(row: $0, model: PreviewModel(), router: PanelRouter()) }
    }
    .padding()
    .frame(width: 520)
    .background(.black)
    .environment(\.colorScheme, .dark)
}
#endif
