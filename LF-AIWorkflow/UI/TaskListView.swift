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
        let items = MergedTaskList.merge(code: model.rows, research: router.research?.rows ?? [])
        if items.isEmpty {
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
                    ForEach(items) { item in
                        switch item {
                        case .code(let row): TaskRowView(row: row, model: model, router: router)
                        case .research(let row):
                            if let research = router.research { ResearchRowView(row: row, research: research, onOpen: { router.show(task: row.id) }) }
                        }
                    }
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
