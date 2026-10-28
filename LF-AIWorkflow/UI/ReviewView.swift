//
//  ReviewView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Review findings for a finished task: severity (text, not color alone), `file:line` that opens in the editor.
struct ReviewView: View {
    @State private var model: ReviewViewModel
    let onDone: () -> Void

    init(task: WorkflowTask, loader: any ReviewLoading = FileReviewLoader(), onDone: @escaping () -> Void) {
        _model = State(initialValue: ReviewViewModel(task: task, loader: loader, opener: EditorOpener()))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Review").font(.system(size: 12, weight: .semibold))
                Text(countsText).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Open worktree") { model.openWorktree() }
                    .accessibilityHint("Shows the task folder in Finder")
                Button("Send HIGH to Fix") {}
                    .disabled(!model.canSendHighToFix)
                    .help(ReviewViewModel.sendHighToFixNote)
                    .accessibilityHint(ReviewViewModel.sendHighToFixNote)
                Button("Done", action: onDone)
            }
            .controlSize(.small)
            if let message = model.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
            }
            if model.isLoaded && model.findings.isEmpty {
                Text("No findings.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.findings.enumerated()), id: \.offset) { _, finding in
                        FindingRow(finding: finding) { model.open(finding) }
                    }
                }
            }
            .frame(maxHeight: 140)
            footer
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .task { await model.load() }
    }

    private var countsText: String {
        let parts = Severity.allCases.compactMap { sev in model.countsBySeverity[sev].map { "\($0) \(sev.label.capitalized)" } }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if let path = model.reportPath {
                Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if model.unparsedCount > 0 {
                Text("\(model.unparsedCount) line(s) could not be read").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct FindingRow: View {
    let finding: Finding
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.severity.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.28)))
                    Text(location).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }
                Text(finding.issue).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if let suggestion = finding.suggestion {
                    Text("Suggestion: \(suggestion)").font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the file in your editor")
    }

    private var location: String { finding.line.map { "\(finding.file):\($0)" } ?? finding.file }

    private var spoken: String {
        let place = finding.line.map { "\(finding.file) line \($0)" } ?? finding.file
        return "\(finding.severity.label.capitalized) severity, \(place), \(finding.issue)"
            + (finding.suggestion.map { ". Suggestion: \($0)" } ?? "")
    }

    private var tint: Color {
        switch finding.severity {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .info: .gray
        }
    }
}

#if DEBUG
#Preview {
    ReviewView(task: PreviewFixtures.task("Done task", state: .done, reviewFile: URL(fileURLWithPath: "/tmp/MyApp/.claude/reviews/done-task.md")), loader: PreviewFixtures.reviewLoader, onDone: {})
        .padding().frame(width: 560, height: 300).background(.black).environment(\.colorScheme, .dark)
}
#endif
