//
//  ResearchRowView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// One research task in the list: question, chips, status and the actions its state allows.
struct ResearchRowView: View {
    let row: ResearchRowModel
    let research: ResearchViewModel
    var onOpen: () -> Void = {}
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(row.question, systemImage: "doc.text.magnifyingglass")
                        .font(theme.headingFont.font).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(TaskFormat.tokens(row.tokensUsed))
                        .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color).monospacedDigit()
                }
                StageChipStrip(displays: row.chips)
                Text(statusText)
                    .font(theme.bodyFont.font)
                    .foregroundStyle(row.needsAttention ? palette.warning.color : palette.secondaryText.color)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Research: \(row.question). \(statusText)")
            actions
        }
        .padding(10)
        .themedSurface(row.needsAttention ? .attentionRow : .row)
    }

    private var statusText: String {
        switch row.state {
        case .queued: "Queued"
        case .capture: "Capturing sources"
        case .clean: "Cleaning pages"
        case .awaitingPreview: "Review the sources, then send"
        case .extract: "Extracting facts"
        case .analyze: "Analyzing"
        case .report: "Writing the report"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .awaitingInput: "Needs your input"
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(row.state == .awaitingPreview ? "Review" : "Details") { onOpen() }
                .accessibilityLabel("Open details for \(row.question)")
            if row.state == .awaitingPreview || row.state == .awaitingInput {
                Button("Send") { Task { await research.send(row.id, excluded: []) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Send sources for \(row.question)")
            }
            if !row.isFinished {
                Button("Cancel", role: .destructive) { Task { await research.cancel(row.id) } }
                    .accessibilityLabel("Cancel research \(row.question)")
            }
        }
        .controlSize(.small)
    }
}
