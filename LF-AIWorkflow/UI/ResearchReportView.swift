//
//  ResearchReportView.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The finished report: sanitized answer, comparison table, export, follow-up. Links open only after the host is confirmed.
struct ResearchReportView: View {
    let model: ResearchReportViewModel
    @State private var pendingLink: URL?
    @State private var exportError: String?
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let report = model.report {
                        Text(SafeMarkdown.attributed(report.answer))
                            .font(theme.bodyLargeFont.font)
                            .textSelection(.enabled)
                            .environment(\.openURL, OpenURLAction { url in
                                if ResearchReportViewModel.confirmationHost(for: url) != nil { pendingLink = url }
                                return .handled
                            })
                        if let table = report.table { ComparisonTableView(table: table) }
                        if !report.unknownCitations.isEmpty {
                            Label("Cites unknown sources: \(report.unknownCitations.map(String.init).joined(separator: ", "))",
                                  systemImage: "exclamationmark.triangle")
                                .font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
                        }
                    } else {
                        Text("The report is not available.").foregroundStyle(palette.secondaryText.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let exportError {
                Text(exportError).font(theme.bodyFont.font).foregroundStyle(palette.failure.color)
            }
            followUp
            HStack(spacing: 8) {
                Button("Open folder") { model.openFolder() }
                    .accessibilityLabel("Show the research folder in Finder")
                Button("Export CSV") { export() }
                    .disabled(model.table == nil)
                    .accessibilityLabel("Export the comparison table as CSV")
            }
            .controlSize(.small)
        }
        .task(id: model.task.reportFile) { await model.loadReport() }
        .confirmationDialog("Open this link?", isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }),
                            presenting: pendingLink) { url in
            Button("Open \(ResearchReportViewModel.confirmationHost(for: url) ?? "link")") { NSWorkspace.shared.open(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text(url.absoluteString)
        }
    }

    private var followUp: some View {
        HStack {
            TextField("Ask a follow-up", text: Bindable(model).followUpText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.ask() } }
                .accessibilityLabel("Follow-up question")
            Button("Ask") { Task { await model.ask() } }
                .disabled(!model.canAsk)
                .accessibilityLabel("Ask the follow-up question")
        }
        .controlSize(.small)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "comparison.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportCSV(to: url); exportError = nil } catch { exportError = "Could not save the CSV: \(error.localizedDescription)" }
    }
}
