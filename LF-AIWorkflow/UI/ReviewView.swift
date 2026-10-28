//
//  ReviewView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Review findings for a finished task: severity (text, not color alone), `file:line` that opens in the editor.
struct ReviewView: View {
    @State private var model: ReviewViewModel
    let onDone: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    init(task: WorkflowTask, loader: any ReviewLoading = FileReviewLoader(), onDone: @escaping () -> Void) {
        _model = State(initialValue: ReviewViewModel(task: task, loader: loader, opener: EditorOpener()))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Review").font(theme.subheadingFont.font)
                Text(countsText).font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
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
                Text(message).font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
            }
            if model.isLoaded && model.findings.isEmpty {
                Text("No findings.").font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
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
        .themedSurface(.row)
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
                Text(path).font(theme.monoFont.font).foregroundStyle(palette.secondaryText.color)
                    .lineLimit(1).truncationMode(.middle)
            }
            if model.unparsedCount > 0 {
                Text("\(model.unparsedCount) line(s) could not be read").font(theme.captionFont.font).foregroundStyle(palette.secondaryText.color)
            }
        }
    }
}

struct FindingRow: View {
    let finding: Finding
    let onOpen: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(finding.severity.label)
                        .font(theme.iconFont.weighted(.bold).font)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: theme.badgeCornerRadius).fill(tint.fading(theme.badgeTintOpacity).color))
                    Text(location).font(theme.monoBodyFont.font).lineLimit(1).truncationMode(.middle)
                }
                Text(finding.issue).font(theme.bodyFont.font).fixedSize(horizontal: false, vertical: true)
                if let suggestion = finding.suggestion {
                    Text("Suggestion: \(suggestion)").font(theme.captionFont.font).foregroundStyle(palette.secondaryText.color)
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

    private var tint: ThemeColor {
        switch finding.severity {
        case .critical: palette.failure
        case .high: palette.warning
        case .medium: palette.caution
        case .low: palette.accent
        case .info: palette.neutral
        }
    }
}

#if DEBUG
#Preview {
    ReviewView(task: PreviewFixtures.task("Done task", state: .done, reviewFile: URL(fileURLWithPath: "/tmp/MyApp/.claude/reviews/done-task.md")), loader: PreviewFixtures.reviewLoader, onDone: {})
        .padding().frame(width: 560, height: 300).background(.black).environment(\.colorScheme, .dark)
}
#endif
