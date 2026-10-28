//
//  AppLog.swift
//  LF-AIWorkflow
//

import os

/// Shared `os.Logger` categories. Loggers are immutable `Sendable` values,
/// so they are reachable from any isolation domain.
nonisolated enum AppLog {
    nonisolated static let subsystem = "com.alifu.LF-AIWorkflow"

    nonisolated static let notch = Logger(subsystem: subsystem, category: "notch")
    nonisolated static let claude = Logger(subsystem: subsystem, category: "claude")
    nonisolated static let workflow = Logger(subsystem: subsystem, category: "workflow")
    nonisolated static let core = Logger(subsystem: subsystem, category: "core")
}
