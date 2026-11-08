//
//  TaskRowModel.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum RowAction: Sendable, Hashable {
    case approve, openPlan, cancel, viewReview, openWorktree, viewPlan, resume, skipTests, retry, removeWorktree
}

/// Pure projection of a `WorkflowTask` for the list and detail views.
nonisolated struct TaskRowModel: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let state: TaskState
    let chips: [StageChip]
    let statusLine: String
    let tokensText: String
    let elapsed: Duration
    /// 0...1 while the task is live, nil once it ended.
    let progress: Double?
    let actions: Set<RowAction>
    /// Tokens added to the budget on Resume; > 0 only for a budget wait (a plain resume re-pauses at once).
    let resumeRaiseTokens: Int
    let resumeLabel: String
    let hasPlanFile: Bool
    let needsAttention: Bool
    let isRunning: Bool
    let createdAt: Date
    let branch: String?
    let worktreePath: String?
    let accessibilityLabel: String

    var elapsedText: String { TaskFormat.clock(elapsed) }

    /// `now` is the clock reading for elapsed time (the board freezes it for finished tasks).
    /// Complexity: O(1) time, O(1) space (five chips)
    init(_ task: WorkflowTask, now: Date, fixLoopCap: Int = 2) {
        let chips = StageChip.chips(for: task, fixLoopCap: fixLoopCap)
        let elapsed = Duration.seconds(max(0, Int(now.timeIntervalSince(task.createdAt))))
        let tokens = task.totalUsage.billableTotal
        id = task.id
        title = task.title
        state = task.state
        self.chips = chips
        statusLine = TaskText.statusLine(task, fixLoopCap: fixLoopCap)
        tokensText = TaskFormat.tokens(tokens) + " tok"
        self.elapsed = elapsed
        progress = task.state.isTerminal || task.state == .awaitingInput ? nil : Self.progress(chips)
        actions = Self.actions(for: task)
        if case .budgetExceeded = task.waitReason {
            resumeRaiseTokens = Self.budgetResumeStep
            resumeLabel = "Resume +\(TaskFormat.tokens(Self.budgetResumeStep)) tokens"
        } else {
            resumeRaiseTokens = 0
            resumeLabel = "Resume"
        }
        hasPlanFile = task.planFile != nil
        needsAttention = Self.attentionStates.contains(task.state)
        isRunning = Self.runningStates.contains(task.state)
        createdAt = task.createdAt
        branch = task.worktree?.branch
        worktreePath = task.worktree?.path.path
        accessibilityLabel = [task.title, TaskText.headline(task.state), tokens > 0 ? TaskFormat.spokenTokens(tokens) : nil,
                              TaskFormat.spokenDuration(elapsed)].compactMap { $0 }.joined(separator: ", ")
    }

    /// Tokens added when resuming a budget-paused task.
    static let budgetResumeStep = 250_000

    static let runningStates: Set<TaskState> = [.plan, .code, .test, .fix, .review]
    static let attentionStates: Set<TaskState> = [.awaitingApproval, .awaitingInput, .failed]

    private static func progress(_ chips: [StageChip]) -> Double {
        guard !chips.isEmpty else { return 0 }
        let score = chips.reduce(0.0) { sum, chip in
            switch chip.status {
            case .done: sum + 1
            case .active: sum + 0.5
            case .pending, .failed: sum
            }
        }
        return score / Double(chips.count)
    }

    private static func actions(for task: WorkflowTask) -> Set<RowAction> {
        var actions: Set<RowAction> = []
        if !task.state.isTerminal { actions.insert(.cancel) }
        if task.state == .awaitingApproval {
            actions.insert(.approve)
            if task.planFile != nil { actions.insert(.openPlan) }
        }
        if task.state == .awaitingInput {
            if task.resumeState != nil { actions.insert(.resume) }
            if task.waitReason?.allowsSkippingTests == true { actions.insert(.skipTests) }
        }
        if task.state == .failed { actions.insert(.retry) }
        if task.reviewFile != nil { actions.insert(.viewReview) }
        if task.planFile != nil { actions.insert(.viewPlan) }
        if task.worktree != nil { actions.insert(.openWorktree) }
        if task.worktree != nil, task.state == .done || task.state == .cancelled { actions.insert(.removeWorktree) }
        return actions
    }
}

/// Human-readable status text, shared by rows, peek messages and VoiceOver.
nonisolated enum TaskText {
    /// Complexity: O(1) time, O(1) space
    static func statusLine(_ task: WorkflowTask, fixLoopCap: Int) -> String {
        switch task.state {
        case .queued: "Queued"
        case .plan: "Planning"
        case .awaitingApproval: "Plan ready, waiting for approval"
        case .code: "Coding"
        case .test: "Running tests"
        case .fix: "Fixing test failures (\(task.fixAttempts)/\(fixLoopCap))"
        case .review: "Reviewing"
        case .done: "Done"
        case .cancelled: "Cancelled"
        case .awaitingInput: waitText(task.waitReason)
        case .failed: failureText(task.failure)
        }
    }

    static func waitText(_ reason: WaitReason?) -> String {
        switch reason {
        case .budgetExceeded(let spent, let limit): "Token budget reached (\(TaskFormat.tokens(spent)) of \(TaskFormat.tokens(limit)))"
        case .dayBudgetExceeded(let spent, let limit): "Daily token budget reached (\(TaskFormat.tokens(spent)) of \(TaskFormat.tokens(limit)))"
        case .noTestCommand: "No test command found"
        case .testTimedOut: "Tests timed out"
        case .testEntryModified(let path): "The code changed \(path), which runs the tests. Review it, then resume"
        case .toolMissing(let tool): "\(tool.displayName) not found"
        case .other(let text): text
        case nil: "Waiting for input"
        }
    }

    static func failureText(_ reason: FailureReason?) -> String {
        switch reason {
        case .claudeError(let text): "Failed: \(text)"
        case .fixLoopExhausted(let attempts): "Tests still failing after \(attempts) fix attempts"
        case .worktree(let text): "Failed: worktree: \(text)"
        case .spawn(let text): "Failed: could not start: \(text)"
        case .invalidCommand(let text): "Failed: invalid command: \(text)"
        case nil: "Failed"
        }
    }

    /// Spoken stage summary: "Code stage running".
    static func headline(_ state: TaskState) -> String {
        switch state {
        case .plan: "Plan stage running"
        case .code: "Code stage running"
        case .test: "Test stage running"
        case .fix: "Fix stage running"
        case .review: "Review stage running"
        case .queued: "Queued"
        case .awaitingApproval: "Plan ready, awaiting approval"
        case .awaitingInput: "Waiting for input"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

nonisolated enum TaskFormat {
    /// "950", "2.2k", "12.4k", "150k", "1.2M".
    /// Complexity: O(1) time, O(1) space
    static func tokens(_ count: Int) -> String {
        let n = max(0, count)
        switch n {
        case ..<1_000: return "\(n)"
        case ..<100_000: return decimal(tenths: (n + 50) / 100) + "k"
        case ..<1_000_000: return "\((n + 500) / 1_000)k"
        default: return decimal(tenths: (n + 50_000) / 100_000) + "M"
        }
    }

    /// "12.4 thousand tokens".
    static func spokenTokens(_ count: Int) -> String {
        var text = tokens(count)
        if text.hasSuffix("k") { text = text.dropLast() + " thousand" }
        if text.hasSuffix("M") { text = text.dropLast() + " million" }
        return text + " tokens"
    }

    /// "00:05", "03:07", "1:02:03".
    /// Complexity: O(1) time, O(1) space
    static func clock(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        let (hours, minutes, seconds) = (total / 3_600, total % 3_600 / 60, total % 60)
        let mmss = String(format: "%02d:%02d", minutes, seconds)
        return hours > 0 ? "\(hours):" + mmss : mmss
    }

    /// "5 seconds", "1 minute", "3 minutes", "2 hours".
    static func spokenDuration(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        func unit(_ value: Int, _ name: String) -> String { "\(value) \(name)\(value == 1 ? "" : "s")" }
        if total < 60 { return unit(total, "second") }
        if total < 3_600 { return unit(total / 60, "minute") }
        return unit(total / 3_600, "hour")
    }

    private static func decimal(tenths: Int) -> String {
        tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}
