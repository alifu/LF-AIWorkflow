//
//  TaskRowModelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite struct TaskRowModelTests {
    private let now = PreviewFixtures.epoch.addingTimeInterval(187)   // 3 min 7 s after creation
    private let plan = URL(fileURLWithPath: "/tmp/plan.md")
    private let review = URL(fileURLWithPath: "/tmp/review.md")

    private func row(_ task: WorkflowTask) -> TaskRowModel { TaskRowModel(task, now: now, fixLoopCap: 2) }
    private func summary(_ chips: [StageChip]) -> [String] {
        chips.map { "\($0.step.rawValue):\($0.status):\($0.detail ?? "-")" }
    }

    // MARK: chips

    @Test func codeStateHasCodeActive() {
        let chips = row(PreviewFixtures.task(state: .code)).chips
        #expect(summary(chips) == ["plan:done:-", "code:active:-", "test:pending:-", "fix:pending:-", "review:pending:-"])
    }

    @Test func fixStateShowsFailedTestAndCounter() {
        let chips = row(PreviewFixtures.task(state: .fix, fixAttempts: 1)).chips
        #expect(summary(chips) == ["plan:done:-", "code:done:-", "test:failed:-", "fix:active:1/2", "review:pending:-"])
    }

    @Test func testStateAfterAFixKeepsTheFixCounterDone() {
        let chips = row(PreviewFixtures.task(state: .test, fixAttempts: 1)).chips
        #expect(summary(chips) == ["plan:done:-", "code:done:-", "test:active:-", "fix:done:1/2", "review:pending:-"])
    }

    @Test func fixChipIsOmittedOnceReviewIsReachedWithoutFixes() {
        #expect(summary(row(PreviewFixtures.task(state: .review)).chips)
                == ["plan:done:-", "code:done:-", "test:done:-", "review:active:-"])
        #expect(summary(row(PreviewFixtures.task(state: .done)).chips)
                == ["plan:done:-", "code:done:-", "test:done:-", "review:done:-"])
    }

    @Test func awaitingApprovalHasPlanDoneCodePending() {
        let chips = row(PreviewFixtures.task(state: .awaitingApproval)).chips
        #expect(chips.first?.status == .done)
        #expect(chips.first { $0.step == .code }?.status == .pending)
    }

    @Test func queuedHasEverythingPending() {
        #expect(row(PreviewFixtures.task(state: .queued)).chips.allSatisfy { $0.status == .pending })
    }

    @Test func exhaustedFixLoopFailsTheTestChip() {
        let task = PreviewFixtures.task(state: .failed, fixAttempts: 2, failure: .fixLoopExhausted(attempts: 2))
        #expect(summary(row(task).chips) == ["plan:done:-", "code:done:-", "test:failed:-", "fix:done:2/2", "review:pending:-"])
    }

    @Test func parkedTaskMarksTheResumeStepActive() {
        let task = PreviewFixtures.task(state: .awaitingInput, wait: .noTestCommand, resume: .test)
        #expect(row(task).chips.first { $0.step == .test }?.status == .active)
    }

    @Test func chipAccessibilityLabels() {
        let chips = row(PreviewFixtures.task(state: .fix, fixAttempts: 1)).chips
        #expect(chips.first?.accessibilityLabel == "Plan, done")
        #expect(chips.first { $0.step == .fix }?.accessibilityLabel == "Fix, active, 1 of 2")
        #expect(chips.first { $0.step == .test }?.accessibilityLabel == "Test, failed")
    }

    // MARK: text

    @Test func tokenFormatting() {
        #expect(TaskFormat.tokens(999) == "999")
        #expect(TaskFormat.tokens(2_200) == "2.2k")
        #expect(TaskFormat.tokens(2_000) == "2k")
        #expect(TaskFormat.tokens(12_400) == "12.4k")
        #expect(TaskFormat.tokens(150_000) == "150k")
        #expect(TaskFormat.tokens(1_200_000) == "1.2M")
        #expect(row(PreviewFixtures.task(tokens: 12_400)).tokensText == "12.4k tok")
    }

    @Test func elapsedFormatting() {
        #expect(TaskFormat.clock(.seconds(5)) == "00:05")
        #expect(TaskFormat.clock(.seconds(187)) == "03:07")
        #expect(TaskFormat.clock(.seconds(3723)) == "1:02:03")
        let r = row(PreviewFixtures.task())
        #expect(r.elapsed == .seconds(187))
        #expect(r.elapsedText == "03:07")
    }

    @Test func statusLines() {
        #expect(row(PreviewFixtures.task(state: .awaitingApproval)).statusLine == "Plan ready, waiting for approval")
        #expect(row(PreviewFixtures.task(state: .fix, fixAttempts: 1)).statusLine == "Fixing test failures (1/2)")
        #expect(row(PreviewFixtures.task(state: .code)).statusLine == "Coding")
        #expect(row(PreviewFixtures.task(state: .done)).statusLine == "Done")
        #expect(row(PreviewFixtures.task(state: .cancelled)).statusLine == "Cancelled")
        #expect(row(PreviewFixtures.task(state: .awaitingInput, wait: .noTestCommand, resume: .test)).statusLine
                == "No test command found")
        #expect(row(PreviewFixtures.task(state: .awaitingInput, wait: .budgetExceeded(spent: 150_000, limit: 150_000),
                                         resume: .code)).statusLine == "Token budget reached (150k of 150k)")
        #expect(row(PreviewFixtures.task(state: .failed, failure: .claudeError("boom"))).statusLine == "Failed: boom")
        #expect(row(PreviewFixtures.task(state: .failed, fixAttempts: 2, failure: .fixLoopExhausted(attempts: 2))).statusLine
                == "Tests still failing after 2 fix attempts")
    }

    @Test func rowAccessibilityLabel() {
        let r = row(PreviewFixtures.task("Login biometric", state: .code, tokens: 12_400))
        #expect(r.accessibilityLabel == "Login biometric, Code stage running, 12.4 thousand tokens, 3 minutes")
    }

    // MARK: actions and flags

    @Test func approveOnlyWhileAwaitingApproval() {
        for state in TaskState.allCases {
            let actions = row(PreviewFixtures.task(state: state, planFile: plan)).actions
            #expect(actions.contains(.approve) == (state == .awaitingApproval), "state \(state)")
        }
        #expect(row(PreviewFixtures.task(state: .awaitingApproval, planFile: plan)).actions.contains(.openPlan))
    }

    @Test func cancelOnlyWhileNotTerminal() {
        #expect(row(PreviewFixtures.task(state: .code)).actions.contains(.cancel))
        #expect(row(PreviewFixtures.task(state: .awaitingInput, wait: .testTimedOut, resume: .test)).actions.contains(.cancel))
        #expect(!row(PreviewFixtures.task(state: .done)).actions.contains(.cancel))
        #expect(!row(PreviewFixtures.task(state: .failed)).actions.contains(.cancel))
    }

    @Test func viewPlanAndViewReviewFollowTheFiles() {
        let bare = row(PreviewFixtures.task(state: .done))
        #expect(!bare.actions.contains(.viewPlan) && !bare.actions.contains(.viewReview) && !bare.hasPlanFile)
        let full = row(PreviewFixtures.task(state: .done, planFile: plan, reviewFile: review))
        #expect(full.actions.isSuperset(of: [.viewPlan, .viewReview]) && full.hasPlanFile)
    }

    @Test func openWorktreeNeedsAWorktree() {
        #expect(!row(PreviewFixtures.task()).actions.contains(.openWorktree))
        let r = row(PreviewFixtures.task(worktree: true))
        #expect(r.actions.contains(.openWorktree) && r.branch == "lf/Login biometric")
    }

    @Test func resumeAndSkipTestsOnlyWhenParkedForTests() {
        let noTests = row(PreviewFixtures.task(state: .awaitingInput, wait: .noTestCommand, resume: .test)).actions
        #expect(noTests.isSuperset(of: [.resume, .skipTests]))
        let budget = row(PreviewFixtures.task(state: .awaitingInput, wait: .budgetExceeded(spent: 1, limit: 1), resume: .code)).actions
        #expect(budget.contains(.resume) && !budget.contains(.skipTests))
        #expect(!row(PreviewFixtures.task(state: .code)).actions.contains(.resume))
    }

    @Test func attentionAndRunningFlags() {
        #expect(row(PreviewFixtures.task(state: .awaitingApproval)).needsAttention)
        #expect(row(PreviewFixtures.task(state: .failed)).needsAttention)
        #expect(row(PreviewFixtures.task(state: .awaitingInput, wait: .noTestCommand, resume: .test)).needsAttention)
        #expect(!row(PreviewFixtures.task(state: .code)).needsAttention)
        #expect(row(PreviewFixtures.task(state: .code)).isRunning)
        #expect(!row(PreviewFixtures.task(state: .awaitingApproval)).isRunning)
        #expect(!row(PreviewFixtures.task(state: .queued)).isRunning)
    }

    @Test func progressOnlyForLiveTasks() {
        #expect(row(PreviewFixtures.task(state: .code)).progress != nil)
        #expect(row(PreviewFixtures.task(state: .done)).progress == nil)
        let p = row(PreviewFixtures.task(state: .code)).progress ?? -1
        #expect(p > 0 && p < 1)
    }

    // MARK: resume raise (HIGH-A)

    @Test func budgetWaitResumeRaisesTheBudgetWithALabelNamingTheStep() {
        let r = row(PreviewFixtures.task(state: .awaitingInput, wait: .budgetExceeded(spent: 500_000, limit: 500_000), resume: .code))
        #expect(r.actions.contains(.resume))
        #expect(r.resumeRaiseTokens == TaskRowModel.budgetResumeStep)
        #expect(r.resumeRaiseTokens > 0)
        #expect(r.resumeLabel == "Resume +\(TaskFormat.tokens(TaskRowModel.budgetResumeStep)) tokens")
    }

    @Test func otherWaitsResumePlainlyWithoutRaisingTheBudget() {
        let r = row(PreviewFixtures.task(state: .awaitingInput, wait: .testTimedOut, resume: .test))
        #expect(r.resumeRaiseTokens == 0)
        #expect(r.resumeLabel == "Resume")
    }
}
