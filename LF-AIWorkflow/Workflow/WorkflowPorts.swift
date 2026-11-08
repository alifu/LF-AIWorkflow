//
//  WorkflowPorts.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct StageRunRequest: Sendable, Equatable {
    let stage: WorkflowStage
    let config: StageConfig
    let prompt: String
    let sessionId: String?
    let addDirs: [URL]
    let workingDirectory: URL
}

nonisolated struct StageRunOutcome: Sendable, Equatable {
    let text: String?
    let sessionId: String?
    let usage: TokenUsage
    let isError: Bool
    let permissionDenials: [String]
    let exitStatus: Int32?
}

nonisolated enum StageRunEvent: Sendable, Equatable {
    case usage(TokenUsage), activity(String), finished(StageRunOutcome)
}

nonisolated protocol ClaudeStageRunning: Sendable {
    func run(_ request: StageRunRequest) -> AsyncThrowingStream<StageRunEvent, Error>
}

nonisolated struct TestCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let display: String
    /// Project-relative file the command executes or is configured by (auto-detected commands only).
    /// The Code/Fix stages can edit it, so a change needs the user's confirmation before the tests run.
    let entryPoint: String?

    init(executable: URL, arguments: [String], display: String, entryPoint: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.display = display
        self.entryPoint = entryPoint
    }
}

nonisolated enum TestOutcome: Sendable, Equatable {
    case passed, failed(exitStatus: Int32, errors: String, truncated: Bool), timedOut, notFound
}

nonisolated protocol TestRunning: Sendable {
    func detect(in root: URL) async -> TestCommand?
    func run(_ cmd: TestCommand, in dir: URL) async -> TestOutcome
}

nonisolated struct GraphNode: Sendable, Equatable {
    let label: String
    let file: String?
    let line: Int?
}

nonisolated struct GraphContext: Sendable, Equatable {
    let text: String
    let nodes: [GraphNode]
    static let empty = GraphContext(text: "", nodes: [])
}

nonisolated protocol GraphQuerying: Sendable {
    func query(_ q: String, root: URL, budgetTokens: Int) async -> GraphContext
    func update(root: URL) async
}

nonisolated enum GitError: Error, Sendable, Equatable {
    case gitNotFound
    case notARepository(String)
    case commandFailed(args: [String], status: Int32, stderr: String)
    case timedOut
    case worktreePathExists(String)
    case branchExists(String)
}

nonisolated protocol GitWorking: Sendable {
    func headCommit(in: URL) async throws(GitError) -> String
    /// A commit-ish capturing the current tracked working tree (HEAD when clean), used as the review base.
    func snapshotCommit(in: URL) async throws(GitError) -> String
    func reviewDiff(in: URL, base: String, markNewFiles: Bool) async throws(GitError) -> String
}

nonisolated protocol WorktreeProviding: Sendable {
    func create(repo: URL, slug: String) async throws(GitError) -> Worktree
    func remove(_ wt: Worktree, repo: URL, force: Bool) async throws(GitError)
}

nonisolated extension TestCommand {
    func withEntryPoint(_ path: String) -> TestCommand {
        TestCommand(executable: executable, arguments: arguments, display: display, entryPoint: path)
    }
}
