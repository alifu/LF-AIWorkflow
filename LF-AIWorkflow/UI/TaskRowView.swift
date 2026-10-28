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
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(theme.headingFont.font).lineLimit(1)
                    Spacer(minLength: 8)
                    ElapsedLabel(row: row)
                    Text(row.tokensText).font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color).monospacedDigit()
                }
                StageChipStrip(chips: row.chips)
                statusLine
                if let progress = row.progress {
                    ThemedProgressBar(value: progress).accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel + ". " + row.statusLine)
            actionBar
        }
        .padding(10)
        .themedSurface(row.needsAttention ? .attentionRow : .row)
        .contextMenu { contextMenu }
    }

    /// Solid themes show an attention row's status as a flat waiting pill; tinted themes keep colored text.
    /// Complexity: O(1) time, O(1) space
    @ViewBuilder private var statusLine: some View {
        if row.needsAttention, theme.statusFills == .solid {
            Text(row.statusLine)
                .font(theme.bodyFont.font)
                .foregroundStyle(palette.onStageFill.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.waitingFill.color))
                .lineLimit(2)
        } else {
            Text(row.statusLine)
                .font(theme.bodyFont.font)
                .foregroundStyle(row.needsAttention ? palette.warning.color : palette.secondaryText.color)
                .lineLimit(2)
        }
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
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

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
        Text(text).font(theme.bodyFont.font).foregroundStyle(theme.palette(for: scheme).secondaryText.color).monospacedDigit()
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
