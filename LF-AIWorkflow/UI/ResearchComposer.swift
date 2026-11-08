//
//  ResearchComposer.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The Research half of the New tab: question, sources, crawl limits, output, Preview and Run.
struct ResearchComposer: View {
    let model: ResearchComposerViewModel
    let hover: HoverController

    @FocusState private var questionFocused: Bool
    @State private var showSetup = false
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want to find out?").font(theme.subheadingFont.font)
                TextEditor(text: Bindable(model).question)
                    .font(theme.bodyLargeFont.font)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 60, maxHeight: 90)
                    .themedSurface(.field)
                    .focused($questionFocused)
                    .accessibilityLabel("Research question")
                tabsSection
                urlSection
                inboxRow
                limitsRow
                optionsRow
                actionRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .onChange(of: questionFocused) { _, focused in hover.setFocusHold(focused) }
        .onDisappear { hover.setFocusHold(false) }
        .task { await model.refreshTabs() }
        .sheet(isPresented: $showSetup) {
            if let guide = model.setupGuide { SafariSetupSheet(guide: guide) { showSetup = false } }
        }
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Safari tabs").font(theme.emphasisFont.font)
                Spacer()
                if model.setupGuide != nil {
                    Button("Set up Safari…") { showSetup = true }.controlSize(.small)
                }
                Button("Refresh") { Task { await model.refreshTabs() } }.controlSize(.small)
                    .accessibilityLabel("Refresh Safari tabs")
            }
            if model.tabs.isEmpty {
                Text(model.setupGuide?.title ?? "No Safari tabs open.")
                    .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            }
            ForEach(model.tabs) { choice in
                Toggle(isOn: Binding(get: { choice.selected }, set: { _ in model.toggle(choice.id) })) {
                    VStack(alignment: .leading) {
                        Text(choice.tab.title).font(theme.bodyFont.font).lineLimit(1)
                        Text(choice.tab.url.host ?? "").font(theme.bodyFont.font)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                }
                .accessibilityLabel("Use tab \(choice.tab.title)")
            }
        }
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("https://…", text: Bindable(model).urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addURL() }
                    .accessibilityLabel("URL to crawl")
                Button("+ Add URL") { model.addURL() }.controlSize(.small)
            }
            if let error = model.urlError {
                Text(error).font(theme.bodyFont.font).foregroundStyle(palette.failure.color)
            }
            ForEach(model.urls, id: \.self) { url in
                AttachmentChip(name: url.absoluteString, detail: nil, removeLabel: "Remove \(url.host ?? "URL")") {
                    model.removeURL(url)
                }
            }
        }
    }

    private var inboxRow: some View {
        HStack {
            Button("Use inbox (\(model.inboxCount))") { Task { await model.useInbox() } }
                .controlSize(.small)
                .disabled(model.inboxCount == 0 && model.inboxPages.isEmpty)
            if !model.inboxPages.isEmpty {
                Text("\(model.inboxPages.count) saved pages").font(theme.bodyFont.font)
                    .foregroundStyle(palette.secondaryText.color)
                Button("Clear") { model.clearInbox() }.controlSize(.small)
            }
        }
    }

    private var limitsRow: some View {
        HStack(spacing: 12) {
            Stepper("Crawl depth \(model.depth)", value: Binding(get: { model.depth }, set: { model.setDepth($0) }), in: 0...2)
            Stepper("Max pages \(model.maxPages)", value: Binding(get: { model.maxPages }, set: { model.setMaxPages($0) }),
                    in: 1...50)
            Text("Same site only").font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
        }
        .font(theme.bodyFont.font)
        .controlSize(.small)
    }

    private var optionsRow: some View {
        HStack {
            Picker("Output", selection: Bindable(model).output) {
                Text("Summary").tag(OutputKind.summary)
                Text("Comparison").tag(OutputKind.comparison)
            }
            .pickerStyle(.segmented).frame(width: 220)
            .accessibilityLabel("Output kind")
            Toggle("Deep analysis (Opus)", isOn: Bindable(model).deep).controlSize(.small)
            Spacer()
            if let tokens = model.estimatedTokens {
                Text("About \(TaskFormat.tokens(tokens)) tokens")
                    .font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if let issue = model.issue {
                Text(issue.message).font(theme.bodyFont.font).foregroundStyle(palette.secondaryText.color)
            }
            Spacer()
            Button("Preview") { Task { await model.submit(run: false) } }
                .disabled(model.issue != nil || model.isSubmitting)
                .accessibilityHint("Shows the cleaned sources before anything is sent to Claude")
            Button("Run") { Task { await model.submit(run: true) } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.issue != nil || model.isSubmitting)
                .accessibilityHint("Previews, then sends if no source is flagged")
        }
    }
}
