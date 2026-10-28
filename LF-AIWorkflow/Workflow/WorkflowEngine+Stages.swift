//
//  WorkflowEngine+Stages.swift
//  LF-AIWorkflow
//

import Foundation
import os

extension WorkflowEngine {
    // MARK: - Queued: worktree

    /// Creates the worktree first, so every stage shares one cwd (Claude stores sessions per cwd).
    /// Complexity: O(1) time, O(1) space (plus the git calls)
    func prepare(_ id: UUID) async {
        guard let task = tasks[id] else { return }
        var worktree: Worktree?
        do {
            if effectiveSettings(for: id).useWorktree {
                worktree = try await deps.worktrees.create(repo: task.projectRoot, slug: task.slug)
            } else {
                baseCommits[id] = try await deps.git.headCommit(in: task.projectRoot)
            }
        } catch {
            if isCurrent(id, .queued) { fail(id, .worktree(Self.describe(error))) }
            return
        }
        guard isCurrent(id, .queued) else { return }
        apply(id, to: .plan) { $0.with(worktree: worktree) }
    }

    // MARK: - Plan

    /// Complexity: O(prompt + plan bytes) time, O(plan bytes) space
    func runPlan(_ id: UUID) async {
        guard let outcome = await runClaude(id, .plan), let task = tasks[id] else { return }
        guard let text = outcome.text, !text.isEmpty else {
            fail(id, .claudeError("the plan stage returned no text")); return
        }
        do {
            let file = try writePlan(text, for: task)
            apply(id, to: .awaitingApproval) { $0.with(planFile: file) }
        } catch {
            fail(id, .claudeError("cannot write the plan file: \(error.localizedDescription)"))
        }
    }

    private func writePlan(_ text: String, for task: WorkflowTask) throws -> URL {
        let dir = task.workingDirectory.appendingPathComponent(".claude/plans", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(task.slug).md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Code

    /// Complexity: O(prompt) time, O(prompt) space
    func runCode(_ id: UUID) async {
        _ = await resolveTestCommand(id)
        guard isCurrent(id, .code) else { return }
        guard await runClaude(id, .code) != nil else { return }
        await deps.graph.update(root: tasks[id]?.workingDirectory ?? URL(fileURLWithPath: "/"))
        guard isCurrent(id, .code) else { return }
        apply(id, to: .test)
    }

    // MARK: - Test

    /// Complexity: O(test output) time, O(errors) space
    func runTests(_ id: UUID) async {
        guard withinBudget(id, estimate: 0), let task = tasks[id] else { return }
        guard let command = await resolveTestCommand(id) else {
            if isCurrent(id, .test) { park(id, .noTestCommand) }
            return
        }
        let outcome = await deps.tests.run(command, in: task.workingDirectory)
        guard isCurrent(id, .test) else { return }
        await log(Self.summary(of: outcome, command: command), id, .test)
        switch outcome {
        case .passed: apply(id, to: .review) { $0.with(lastErrors: nil) }
        case .timedOut: park(id, .testTimedOut)
        case .notFound: park(id, .other("the test tool was not found: \(command.display)"))
        case .failed(_, let errors, _):
            guard task.fixAttempts < effectiveSettings(for: id).fixLoopCap else {
                fail(id, .fixLoopExhausted(attempts: task.fixAttempts)); return
            }
            apply(id, to: .fix) { $0.with(lastErrors: errors) }
        }
    }

    // MARK: - Fix

    /// Complexity: O(prompt) time, O(prompt) space
    func runFix(_ id: UUID) async {
        guard await runClaude(id, .fix) != nil else { return }
        await deps.graph.update(root: tasks[id]?.workingDirectory ?? URL(fileURLWithPath: "/"))
        guard isCurrent(id, .fix) else { return }
        apply(id, to: .test)
    }

    // MARK: - Review

    /// Complexity: O(diff bytes) time, O(diff bytes) space
    func runReview(_ id: UUID) async {
        guard let outcome = await runClaude(id, .review), let task = tasks[id] else { return }
        let report = ReviewReport.parse(outcome.text ?? "")
        do {
            let file = try report.save(projectRoot: task.workingDirectory, slug: task.slug)
            apply(id, to: .done) { $0.with(reviewFile: file) }
        } catch {
            fail(id, .claudeError("cannot save the review report: \(error.localizedDescription)"))
        }
    }

    // MARK: - Shared stage execution

    /// Budget check, prompt, run. Returns the outcome only when the task is still in the stage's state;
    /// parks, fails or stays silent (cancelled) otherwise.
    func runClaude(_ id: UUID, _ stage: WorkflowStage) async -> StageRunOutcome? {
        let state = stage.taskState
        guard let task = tasks[id], let prompt = await buildPrompt(for: task, stage: stage), isCurrent(id, state),
              withinBudget(id, estimate: prompt.estimatedTokens), let current = tasks[id] else { return nil }
        let request = StageRunRequest(
            stage: stage, config: effectiveConfig(for: current, stage: stage), prompt: prompt.text,
            sessionId: effectiveSettings(for: id).resumeSessionFor.contains(stage) ? current.sessionId : nil,
            addDirs: prompt.addDirs, workingDirectory: current.workingDirectory)
        return await stream(request, id: id, state: state)
    }

    private func stream(_ request: StageRunRequest, id: UUID, state: TaskState) async -> StageRunOutcome? {
        var lastUsage = TokenUsage.zero
        var finished: StageRunOutcome?
        do {
            for try await event in deps.claude.run(request) {
                switch event {
                case .usage(let usage): lastUsage = usage
                case .activity(let line): await log(line, id, state)
                case .finished(let outcome): finished = outcome
                }
            }
        } catch {
            record(usage: lastUsage, stage: request.stage, id: id)
            if isCurrent(id, state) {
                await log("failed: \(error)", id, state)
                fail(id, error is ClaudeCommandError ? .invalidCommand("\(error)") : .claudeError("\(error)"))
            }
            return nil
        }
        record(usage: finished?.usage ?? lastUsage, stage: request.stage, id: id, session: finished?.sessionId)
        guard isCurrent(id, state) else { return nil }
        guard let outcome = finished else {
            await log("the \(request.stage.displayName) stage ended without a result", id, state)
            fail(id, .claudeError("the \(request.stage.displayName) stage ended without a result")); return nil
        }
        if outcome.isError {
            await log("failed: \(outcome.text ?? "claude reported an error")", id, state)
            fail(id, .claudeError(outcome.text ?? "claude reported an error")); return nil
        }
        return outcome
    }

    /// Writes one line to the optional activity sink.
    func log(_ text: String, _ id: UUID, _ state: TaskState) async {
        await deps.log?.append(text, stage: state, to: id)
    }

    /// One-line test result for the log. Complexity: O(1) time, O(1) space
    static func summary(of outcome: TestOutcome, command: TestCommand) -> String {
        switch outcome {
        case .passed: "tests passed: \(command.display)"
        case .failed(let status, let errors, _): "tests failed (exit \(status)): \(command.display)\n\(errors)"
        case .timedOut: "tests timed out: \(command.display)"
        case .notFound: "test tool not found: \(command.display)"
        }
    }

    private func record(usage: TokenUsage, stage: WorkflowStage, id: UUID, session: String? = nil) {
        guard usage != .zero || session != nil else { return }
        update(id) { task in
            let added = task.adding(usage: usage, for: stage)
            return session.map { added.with(sessionId: $0) } ?? added
        }
    }

    /// Pauses (awaitingInput) when spend plus the next prompt would pass the per-task limit.
    func withinBudget(_ id: UUID, estimate: Int) -> Bool {
        guard let task = tasks[id] else { return false }
        switch (budgets[id] ?? effectiveSettings(for: task.id).budget).check(spent: task.totalUsage, nextEstimate: estimate) {
        case .proceed: return true
        case .pause(let spent, let limit):
            park(id, .budgetExceeded(spent: spent, limit: limit))
            return false
        }
    }

    /// Stage config; Fix escalates the model from the second attempt; the test command joins the allowed tools
    /// of Code and Fix only when `ClaudeCommandBuilder` accepts the resulting rule.
    func effectiveConfig(for task: WorkflowTask, stage: WorkflowStage) -> StageConfig {
        let base = effectiveSettings(for: task.id).policy.config(for: stage)
        var model = base.model
        if stage == .fix, task.fixAttempts >= 2, let escalated = base.escalationModel { model = escalated }
        var tools = base.allowedTools
        if stage == .code || stage == .fix, let display = task.testCommandDisplay, !tools.contains("Bash(\(display))") {
            let candidate = tools + ["Bash(\(display))"]
            let probe = Self.config(base, model: model, tools: candidate)
            if (try? ClaudeCommandBuilder.arguments(config: probe, sessionId: nil, addDirs: [])) != nil {
                tools = candidate
            } else {
                AppLog.workflow.warning("test command not usable as a Claude tool rule; omitted")
            }
        }
        return Self.config(base, model: model, tools: tools)
    }

    private static func config(_ base: StageConfig, model: String, tools: [String]) -> StageConfig {
        StageConfig(model: model, escalationModel: base.escalationModel, permissionMode: base.permissionMode,
                    allowedTools: tools, disallowedTools: base.disallowedTools, maxTurns: base.maxTurns,
                    builtinTools: base.builtinTools, isolated: base.isolated, appendSystemPrompt: base.appendSystemPrompt)
    }

    /// Override first, then detection. Caches the command and its display on the task.
    func resolveTestCommand(_ id: UUID) async -> TestCommand? {
        if let cached = testCommands[id] { return cached }
        guard let task = tasks[id] else { return nil }
        let command: TestCommand?
        if let override = effectiveSettings(for: id).testCommandOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            command = TestCommand(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", override], display: override)
        } else {
            command = await deps.tests.detect(in: task.workingDirectory)
        }
        guard let command else { return nil }
        testCommands[id] = command
        update(id) { $0.with(testCommandDisplay: command.display) }
        return command
    }

    static func describe(_ error: GitError) -> String {
        switch error {
        case .gitNotFound: "git was not found. Install it or set its path in Settings."
        case .notARepository(let path): "\(path) is not a git repository."
        case .commandFailed(_, _, let stderr): stderr.isEmpty ? "git command failed" : stderr
        case .timedOut: "git timed out."
        case .worktreePathExists(let path): "worktree path already exists: \(path)"
        case .branchExists(let branch): "branch already exists: \(branch)"
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? GitError).map { describe($0) } ?? "\(error)"
    }
}
