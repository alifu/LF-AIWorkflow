//
//  ProcessInvocation.swift
//  LF-AIWorkflow
//

import Foundation

/// Everything needed to spawn one child process. The prompt travels via `stdin`, never argv.
nonisolated struct ProcessInvocation: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL
    let stdin: Data
}
