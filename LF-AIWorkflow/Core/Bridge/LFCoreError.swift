//
//  LFCoreError.swift
//  LF-AIWorkflow
//

import Foundation

/// Errors surfaced by the Swift bridges over the C core.
nonisolated enum LFCoreError: Error, Sendable, Equatable {
    /// A C function failed and set `errno` to the carried value.
    case posix(Int32)
}
