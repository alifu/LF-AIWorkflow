//
//  NotchPanelState.swift
//  LF-AIWorkflow
//

nonisolated enum NotchPanelState: Sendable, Equatable {
    case collapsed, peek, expanded, pinned
}

/// Why the panel is expanded. Hover must never take keystrokes from the frontmost app; the rest may (TD-065).
nonisolated enum ExpandReason: Sendable, Equatable {
    case hover, explicit
}
