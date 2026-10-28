//
//  TaskListView.swift
//  LF-AIWorkflow
//

import SwiftUI

struct TaskListView: View {
    let model: any WorkflowControlling
    let router: PanelRouter

    var body: some View {
        if model.rows.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("No tasks").font(.system(size: 14, weight: .semibold))
                Text("Open the New tab to start one.").font(.system(size: 12)).foregroundStyle(.secondary)
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
