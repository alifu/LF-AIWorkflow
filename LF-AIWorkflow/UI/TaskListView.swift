//
//  TaskListView.swift
//  LF-AIWorkflow
//

import SwiftUI

struct TaskListView: View {
    let model: any WorkflowControlling
    let router: PanelRouter
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = theme.palette(for: scheme)
        if model.rows.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("No tasks").font(theme.titleFont.font)
                Text("Open the New tab to start one.").font(theme.bodyLargeFont.font).foregroundStyle(palette.secondaryText.color)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.rows) { TaskRowView(row: $0, model: model, router: router) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}

#if DEBUG
#Preview("Tasks") {
    TaskListView(model: PreviewModel(), router: PanelRouter())
        .frame(width: 560, height: 320).background(.black).environment(\.colorScheme, .dark)
}

#Preview("Empty") {
    TaskListView(model: PreviewModel(rows: []), router: PanelRouter())
        .frame(width: 560, height: 320).background(.black).environment(\.colorScheme, .dark)
}
#endif
