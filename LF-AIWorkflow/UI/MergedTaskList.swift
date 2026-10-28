//
//  MergedTaskList.swift
//  LF-AIWorkflow
//

import Foundation

/// One entry of the task list: a Code task or a Research task.
nonisolated enum TaskListItem: Sendable, Equatable, Identifiable {
    case code(TaskRowModel)
    case research(ResearchRowModel)

    var id: UUID {
        switch self {
        case .code(let row): row.id
        case .research(let row): row.id
        }
    }

    var createdAt: Date {
        switch self {
        case .code(let row): row.createdAt
        case .research(let row): row.createdAt
        }
    }
}

nonisolated enum MergedTaskList {
    /// Both kinds in one list, newest first (ties broken by id so the order is stable).
    /// Complexity: O(n log n) time, O(n) space
    static func merge(code: [TaskRowModel], research: [ResearchRowModel]) -> [TaskListItem] {
        let items = code.map(TaskListItem.code) + research.map(TaskListItem.research)
        return items.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }
}
