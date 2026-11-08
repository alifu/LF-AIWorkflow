//
//  LFCoreError.swift
//  LF-AIWorkflow
//

import Foundation

/// Errors surfaced by the Swift bridges over the C core.
nonisolated enum LFCoreError: Error, Sendable, Equatable {
    /// A C function failed and set `errno` to the carried value.
    case posix(Int32)
    /// The C walk reported a file count that disagrees with the files it delivered. Checked in every build configuration.
    case scanCountMismatch(reported: Int, collected: Int)
}
