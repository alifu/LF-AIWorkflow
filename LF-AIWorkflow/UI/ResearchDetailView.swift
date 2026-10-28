//
//  ResearchDetailView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// One research task in detail: chips and status, then the preview, the report or the failure.
struct ResearchDetailView: View {
    let row: ResearchRowModel?
    let research: ResearchViewModel
    let router: PanelRouter
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
                Text(row?.question ?? "Research").font(theme.titleFont.font).lineLimit(1)
                Spacer()
            }
            if let row, let task = research.task(row.id), let model = research.reportModel(for: row.id) {
                StageChipStrip(displays: row.chips)
                content(task: task, model: model)
            } else {
                Text("This task is no longer listed.").foregroundStyle(palette.secondaryText.color)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func content(task: ResearchTask, model: ResearchReportViewModel) -> some View {
        switch task.state {
        case .awaitingPreview:
            if let preview = task.preview { SourcesPreviewView(preview: preview, model: model) }
        case .done:
            ResearchReportView(model: model)
        case .failed:
            Text(task.errorMessage ?? "Research failed.").foregroundStyle(palette.failure.color)
            denials(task)
        default:
            Text("Working on it").foregroundStyle(palette.secondaryText.color)
            denials(task)
        }
    }

    @ViewBuilder private func denials(_ task: ResearchTask) -> some View {
        if !task.denials.isEmpty {
            Label("Claude tried a blocked tool: \(task.denials.joined(separator: ", "))", systemImage: "exclamationmark.shield")
                .font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
        }
    }
}
