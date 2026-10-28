//
//  SourcesPreviewView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// What was captured, before anything reaches Claude: untick a source to leave it out, then send.
struct SourcesPreviewView: View {
    let preview: SourcesPreview
    let model: ResearchReportViewModel
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(preview.rows, id: \.index) { row in sourceRow(row) }
                }
            }
            Text("Removed as boilerplate: \(preview.removedLines) lines · about \(TaskFormat.tokens(preview.totalTokens))")
                .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            HStack(spacing: 8) {
                Button("Open folder") { model.openFolder() }
                    .accessibilityLabel("Show the research folder in Finder")
                Spacer()
                Button("Cancel", role: .destructive) { Task { await model.cancel() } }
                    .accessibilityLabel("Cancel this research")
                Button("Send") { Task { await model.sendSelected() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.excluded.count >= preview.rows.count)
                    .accessibilityLabel("Send the selected sources to Claude")
            }
            .controlSize(.small)
        }
    }

    private func sourceRow(_ row: SourcesPreviewRow) -> some View {
        let included = !model.excluded.contains(row.index)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(isOn: Binding(get: { included }, set: { _ in model.toggle(row.index) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title.isEmpty ? row.host : row.title).font(theme.emphasisFont.font).lineLimit(1)
                    Text("\(row.host) · \(TaskFormat.tokens(row.tokens)) · \(row.tables) tables")
                        .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Label(flagText(row), systemImage: flagIcon(row))
                .font(theme.bodyFont.font)
                .foregroundStyle(flagged(row) ? palette.warning.color : palette.success.color)
        }
        .padding(8)
        .themedSurface(flagged(row) ? .attentionRow : .row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source \(row.index): \(row.title). \(flagText(row)). \(included ? "Included" : "Excluded")")
    }

    private func flagged(_ row: SourcesPreviewRow) -> Bool {
        !row.flags.isDisjoint(with: [.looksEmpty, .duplicate])
    }

    private func flagIcon(_ row: SourcesPreviewRow) -> String {
        if row.flags.contains(.looksEmpty) { return "xmark.octagon" }
        return flagged(row) ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private func flagText(_ row: SourcesPreviewRow) -> String {
        if row.flags.contains(.looksEmpty) { return "Looks empty" }
        if row.flags.contains(.duplicate) { return "Duplicate" }
        return "OK"
    }
}
