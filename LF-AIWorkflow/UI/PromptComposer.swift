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

    private var composer: ComposerViewModel { router.composer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should Claude build?").font(.system(size: 12, weight: .semibold))
                TextEditor(text: Bindable(composer).prompt)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 70, maxHeight: 110)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
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
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Documents").font(.system(size: 11, weight: .semibold))
                Text(composer.documentLimitText).font(.system(size: 11)).foregroundStyle(.secondary)
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
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? Color.accentColor : .white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4])))
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
                .font(.system(size: 11)).foregroundStyle(.orange)
            HStack {
                Button("Attach anyway") { composer.confirmSecrets() }
                Button("Skip them") { composer.discardSecrets() }.keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Secret files warning")
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Skill folders").font(.system(size: 11, weight: .semibold))
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
                    Text(text).font(.system(size: 11)).foregroundStyle(.orange)
                }
                Button("Dismiss") { composer.dismissNotices() }.controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Attachment messages")
        }
    }

    /// Both are disabled: the engine has no Start-at-Code entry (no queued to code edge) and the worktree setting is
    /// global (TD-044).
    private var optionsRow: some View {
        HStack(spacing: 14) {
            Toggle("Start at Code", isOn: .constant(false)).disabled(true)
                .help("Not available yet: every task starts with a plan")
            Toggle("Use worktree", isOn: .constant(true)).disabled(true)
                .help("Set globally for now: per-task choice is not available yet")
        }
        .font(.system(size: 11)).controlSize(.small)
    }

    private var startRow: some View {
        HStack {
            Text("About \(TaskFormat.tokens(composer.estimatedTokens)) tokens in the first prompt")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc").font(.system(size: 10)).accessibilityHidden(true)
            Text(name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            if let detail { Text("(\(detail))").font(.system(size: 10)).foregroundStyle(.orange) }
            Spacer()
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel(removeLabel)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    PromptComposer(model: PreviewModel(), hover: HoverController(), router: PanelRouter())
        .frame(width: 560, height: 420).background(.black).environment(\.colorScheme, .dark)
}
#endif
