//
//  TerminalTabView.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// Read-only activity log (ANSI already stripped): monospaced, follows the newest line, Copy button.
struct TerminalTabView: View {
    let lines: [TaskLogLine]
    let onCopy: () -> Void
    var caption = "Live output · read-only"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Copy", action: onCopy)
                    .controlSize(.small)
                    .disabled(lines.isEmpty)
                    .accessibilityLabel("Copy output")
            }
            logBody
        }
    }

    @ViewBuilder private var logBody: some View {
        if lines.isEmpty {
            Text("No output yet").font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)))
                .onChange(of: lines.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onAppear { if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
            }
            .accessibilityLabel("Task output")
        }
    }
}

/// Loads the (capped) log of one task and reloads it when new lines arrive. Exists only while visible, so there
/// is no polling when the tab or detail is not on screen.
struct TaskLogPane: View {
    let model: any WorkflowControlling
    let taskID: UUID?
    var caption = "Live output · read-only"
    @State private var lines: [TaskLogLine] = []

    private struct LoadKey: Equatable { let id: UUID?; let revision: Int }

    var body: some View {
        TerminalTabView(lines: lines, onCopy: copy, caption: caption)
            .task(id: LoadKey(id: taskID, revision: model.logRevision)) {
                guard let taskID else { lines = []; return }
                lines = TerminalText.tail(await model.log(for: taskID))
            }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TerminalText.copyText(lines), forType: .string)
    }
}

/// The Terminal tab: shows the open task, else the newest running one, else the newest.
struct TerminalTabHost: View {
    let model: any WorkflowControlling
    let router: PanelRouter

    var body: some View {
        let row = model.rows.first { $0.id == router.detailTaskID } ?? model.rows.first { $0.isRunning } ?? model.rows.first
        TaskLogPane(model: model, taskID: row?.id,
                    caption: row.map { "Live output · \($0.title) · read-only" } ?? "Live output · read-only")
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("With output") {
    TerminalTabView(lines: (0..<12).map { TaskLogLine(id: $0, stage: .code, text: "Editing Sources/File\($0).swift") }, onCopy: {})
        .padding().frame(width: 520, height: 260).background(.black).environment(\.colorScheme, .dark)
}

#Preview("Empty") {
    TerminalTabView(lines: [], onCopy: {})
        .padding().frame(width: 520, height: 200).background(.black).environment(\.colorScheme, .dark)
}
#endif
