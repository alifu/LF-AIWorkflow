//
//  WorkflowFakes.swift
//  LF-AIWorkflowTests
//

import Foundation
import os
@testable import LF_AIWorkflow

/// Scripted Claude runner: one queue of scripts per stage, a call log, and a record of terminated streams.
final class FakeClaudeRunner: ClaudeStageRunning {
    enum Script: Sendable {
        case outcome(StageRunOutcome)
        case fail(any Error)
        case hang
    }

    private struct State {
        var scripts: [WorkflowStage: [Script]] = [:]
        var calls: [StageRunRequest] = []
        var started: [WorkflowStage] = []
        var terminated: [WorkflowStage] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    static func ok(_ text: String = "ok", session: String? = "11111111-1111-4111-8111-111111111111",
                   tokens: Int = 100) -> StageRunOutcome {
        StageRunOutcome(text: text, sessionId: session, usage: TokenUsage(input: tokens, output: 0, cacheRead: 0, cacheCreation: 0),
                        isError: false, permissionDenials: [], exitStatus: 0)
    }

    static func error(_ text: String = "boom") -> StageRunOutcome {
        StageRunOutcome(text: text, sessionId: nil, usage: .zero, isError: true, permissionDenials: [], exitStatus: 1)
    }

    func script(_ stage: WorkflowStage, _ scripts: Script...) {
        state.withLock { $0.scripts[stage, default: []].append(contentsOf: scripts) }
    }

    var calls: [StageRunRequest] { state.withLock { $0.calls } }
    var terminated: [WorkflowStage] { state.withLock { $0.terminated } }
    func calls(for stage: WorkflowStage) -> [StageRunRequest] { calls.filter { $0.stage == stage } }

    func waitUntilStarted(_ stage: WorkflowStage) async -> Bool {
        for _ in 0..<500 {
            if state.withLock({ $0.started.contains(stage) }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func waitUntilTerminated(_ stage: WorkflowStage) async -> Bool {
        for _ in 0..<500 {
            if terminated.contains(stage) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func run(_ request: StageRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        let script: Script = state.withLock {
            $0.calls.append(request)
            $0.started.append(request.stage)
            guard var queue = $0.scripts[request.stage], !queue.isEmpty else { return .outcome(Self.ok()) }
            let next = queue.removeFirst()
            $0.scripts[request.stage] = queue
            return next
        }
        let (stream, continuation) = AsyncThrowingStream<StageRunEvent, Error>.makeStream()
        continuation.onTermination = { [state] _ in state.withLock { $0.terminated.append(request.stage) } }
        switch script {
        case .outcome(let outcome):
            continuation.yield(.usage(outcome.usage))
            continuation.yield(.finished(outcome))
            continuation.finish()
        case .fail(let error): continuation.finish(throwing: error)
        case .hang: break
        }
        return stream
    }
}

final class FakeTestRunner: TestRunning {
    enum Script: Sendable { case outcome(TestOutcome), hang }

    private struct State {
        var command: TestCommand?
        var scripts: [Script] = []
        var runs: [(TestCommand, URL)] = []
        var detectRoots: [URL] = []
        var cancelled = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(command: TestCommand? = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], display: "make test")) {
        state = OSAllocatedUnfairLock(initialState: State(command: command))
    }

    func script(_ scripts: Script...) { state.withLock { $0.scripts.append(contentsOf: scripts) } }
    var runCount: Int { state.withLock { $0.runs.count } }
    var cancelledRuns: Int { state.withLock { $0.cancelled } }
    var runDirectories: [URL] { state.withLock { $0.runs.map(\.1) } }
    var detectRoots: [URL] { state.withLock { $0.detectRoots } }

    func waitUntilRunning() async -> Bool {
        for _ in 0..<500 {
            if runCount > 0 { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func detect(in root: URL) async -> TestCommand? {
        state.withLock { $0.detectRoots.append(root); return $0.command }
    }

    func run(_ cmd: TestCommand, in dir: URL) async -> TestOutcome {
        let script: Script = state.withLock {
            $0.runs.append((cmd, dir))
            return $0.scripts.isEmpty ? .outcome(.passed) : $0.scripts.removeFirst()
        }
        switch script {
        case .outcome(let outcome): return outcome
        case .hang:
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            state.withLock { $0.cancelled += 1 }
            return .failed(exitStatus: 143, errors: "killed", truncated: false)
        }
    }
}

final class FakeGraph: GraphQuerying {
    private struct State { var context = GraphContext.empty; var queries: [String] = []; var updates = 0 }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(context: GraphContext = .empty) { state.withLock { $0.context = context } }

    var updateCount: Int { state.withLock { $0.updates } }
    var queries: [String] { state.withLock { $0.queries } }

    func query(_ q: String, root: URL, budgetTokens: Int) async -> GraphContext {
        state.withLock { $0.queries.append(q); return $0.context }
    }

    func update(root: URL) async { state.withLock { $0.updates += 1 } }
}

final class FakeGit: GitWorking {
    private struct State { var head = "abc123"; var diff = "diff --git a/a.swift b/a.swift\n+let a = 2\n"; var diffBases: [String] = []; var markFlags: [Bool] = []; var diffError: GitError? }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var diffBases: [String] { state.withLock { $0.diffBases } }
    var markFlags: [Bool] { state.withLock { $0.markFlags } }
    func failDiff(with error: GitError) { state.withLock { $0.diffError = error } }

    func headCommit(in: URL) async throws(GitError) -> String { state.withLock { $0.head } }

    func reviewDiff(in: URL, base: String, markNewFiles: Bool) async throws(GitError) -> String {
        let (diff, error) = state.withLock { state -> (String, GitError?) in
            state.diffBases.append(base)
            state.markFlags.append(markNewFiles)
            return (state.diff, state.diffError)
        }
        if let error { throw error }
        return diff
    }
}

final class FakeWorktrees: WorktreeProviding {
    private struct State { var error: GitError?; var created: [(URL, String)] = [] }
    private let state = OSAllocatedUnfairLock(initialState: State())
    let directory: URL

    init(directory: URL, error: GitError? = nil) {
        self.directory = directory
        state.withLock { $0.error = error }
    }

    var created: [(repo: URL, slug: String)] { state.withLock { $0.created.map { (repo: $0.0, slug: $0.1) } } }

    func create(repo: URL, slug: String) async throws(GitError) -> Worktree {
        if let error = state.withLock({ $0.error }) { throw error }
        state.withLock { $0.created.append((repo, slug)) }
        let path = directory.appendingPathComponent("wt-\(slug)", isDirectory: true)
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return Worktree(path: path, branch: "ai/\(slug)", baseCommit: "base123")
    }

    func remove(_ wt: Worktree, repo: URL, force: Bool) async throws(GitError) {}
}
