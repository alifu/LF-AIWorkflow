//
//  PromptComposer.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The New tab: prompt, project, documents (drop or pick), skill folders, options, token estimate, Start.
struct PromptComposer: View {
    let model: any WorkflowControlling
    let hover: HoverController
    let router: PanelRouter

    @FocusState private var promptFocused: Bool
    @State private var isDropTargeted = false
    @State private var isPicking = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    private var composer: ComposerViewModel { router.composer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should Claude build?").font(theme.subheadingFont.font)
                TextEditor(text: Bindable(composer).prompt)
                    .font(theme.bodyLargeFont.font)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 70, maxHeight: 110)
                    .themedSurface(.field)
                    .focused($promptFocused)
                    .accessibilityLabel("Task prompt")
                projectRow
                documentsSection
                skillSection
                notices
                optionsRow
                startRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .onChange(of: promptFocused) { _, _ in updateFocusHold() }
        .onChange(of: isPicking) { _, _ in updateFocusHold() }
        .onAppear { composer.reacquireAccess() }
        .onDisappear { hover.setFocusHold(false); composer.releaseAccess() }
    }

    // MARK: - Sections

    private var projectRow: some View {
        HStack {
            Button("Choose project…") { pick { await composer.chooseProject() } }.controlSize(.small)
            Text(composer.projectRoot?.path ?? "No project chosen")
                .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color).lineLimit(1).truncationMode(.middle)
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Documents").font(theme.emphasisFont.font)
                Text(composer.documentLimitText).font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
                Spacer()
                Button("Choose files…") { pick { await composer.pickDocuments() } }.controlSize(.small)
            }
            dropZone
            ForEach(composer.documents) { document in
                AttachmentChip(name: document.name, detail: document.isSecret ? "secret file" : nil,
                               removeLabel: "Remove \(document.name)") { composer.removeDocument(document.url) }
            }
            if !composer.pendingSecrets.isEmpty { secretsWarning }
        }
    }

    private var dropZone: some View {
        Text("Drop documents here")
            .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: theme.smallCornerRadius)
                .strokeBorder(isDropTargeted ? palette.accent.color : palette.dropBorder.color, style: StrokeStyle(lineWidth: 1, dash: [4])))
            .dropDestination(for: URL.self) { urls, _ in
                Task { await composer.addDocuments(urls) }
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drop documents here")
            .accessibilityHint("Or use Choose files. Documents are passed to Claude as paths")
    }

    private var secretsWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("These files may contain secrets: \(composer.pendingSecrets.map(\.name).joined(separator: ", ")). "
                  + "Claude would be told to read them.", systemImage: "exclamationmark.triangle.fill")
                .font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
            HStack {
                Button("Attach anyway") { composer.confirmSecrets() }
                Button("Skip them") { composer.discardSecrets() }.keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: theme.smallCornerRadius).fill(palette.warning.fading(theme.subtleTintOpacity).color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Secret files warning")
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Skill folders").font(theme.emphasisFont.font)
                Spacer()
                Button("Add skill folder…") { pick { await composer.pickSkillFolder() } }
                    .controlSize(.small)
                    .disabled(composer.projectRoot == nil)
                    .accessibilityHint(composer.projectRoot == nil ? "Choose a project first" : "Remembered for this project")
            }
            ForEach(composer.skillDirs, id: \.self) { dir in
                AttachmentChip(name: dir.lastPathComponent, detail: nil, removeLabel: "Remove skill folder \(dir.lastPathComponent)") {
                    composer.removeSkillFolder(dir)
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if !composer.notices.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(composer.notices.enumerated()), id: \.offset) { _, text in
                    Text(text).font(theme.bodyFont.font).foregroundStyle(palette.warning.color)
                }
                Button("Dismiss") { composer.dismissNotices() }.controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Attachment messages")
        }
    }

    private var optionsRow: some View {
        HStack(spacing: 14) {
            Toggle("Start at Code", isOn: Bindable(composer).startAtCode)
                .help("Skip the plan and its approval; the first stage is Code")
            Toggle("Use worktree", isOn: Bindable(composer).useWorktree)
                .help("Work in a separate git worktree instead of the project folder")
        }
        .font(theme.bodyFont.font).controlSize(.small)
    }

    private var startRow: some View {
        HStack {
            Text("About \(TaskFormat.tokens(composer.estimatedTokens)) tokens in the first prompt")
                .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
                .accessibilityLabel("Estimated tokens")
                .accessibilityValue("\(composer.estimatedTokens)")
            Spacer()
            Button("Start") { start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!composer.canStart)
                .accessibilityHint(composer.canStart ? "Creates the task and starts planning" : "Needs a prompt and a project")
        }
    }

    // MARK: - Actions

    private func start() {
        guard let draft = composer.makeDraft() else { return }
        composer.reset()
        router.tab = .tasks
        Task { await model.submit(draft) }
    }

    /// Keeps the panel open while a file dialog is up.
    private func pick(_ action: @escaping @MainActor () async -> Void) {
        Task {
            isPicking = true
            await action()
            isPicking = false
        }
    }

    private func updateFocusHold() { hover.setFocusHold(promptFocused || isPicking) }
}

/// A removable attachment row.
struct AttachmentChip: View {
    let name: String
    let detail: String?
    let removeLabel: String
    let onRemove: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = theme.palette(for: scheme)
        HStack(spacing: 6) {
            Image(systemName: "doc").font(theme.captionFont.font).accessibilityHidden(true)
            Text(name).font(theme.bodyFont.font).lineLimit(1).truncationMode(.middle)
            if let detail { Text("(\(detail))").font(theme.captionFont.font).foregroundStyle(palette.warning.color) }
            Spacer()
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel(removeLabel)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .themedSurface(.tag)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    PromptComposer(model: PreviewModel(), hover: HoverController(), router: PanelRouter())
        .frame(width: 560, height: 420).background(.black).environment(\.colorScheme, .dark)
}
#endif
