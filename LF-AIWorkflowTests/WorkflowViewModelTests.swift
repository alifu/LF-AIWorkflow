//
//  WorkflowViewModelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct WorkflowViewModelTests {
    private func makeModel(clock: any Clock<Duration> = ContinuousClock(), harness: Harness? = nil,
                           logs: TaskLogStore = TaskLogStore(),
                           reviewLoader: any ReviewLoading = StubReviewLoader(report: nil)) throws -> (WorkflowViewModel, Harness) {
        let h = try harness ?? Harness(recording: false)
        return (WorkflowViewModel(engine: h.engine, logs: logs, clock: clock, reviewLoader: reviewLoader), h)
    }

    private func settle() async { for _ in 0..<8 { await Task.yield() } }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: coalescing

    @Test func firstUpdatePublishesImmediatelyThenBurstsAreCoalesced() async throws {
        let clock = ManualClock()
        let (model, _) = try makeModel(clock: clock)
        let id = UUID()
        model.receive(PreviewFixtures.task("T", state: .plan, id: id))
        #expect(model.rows.first?.state == .plan)
        await clock.waitForSleepers(1)
        for state in [TaskState.code, .test, .review] { model.receive(PreviewFixtures.task("T", state: state, id: id)) }
        #expect(model.rows.first?.state == .plan)          // still inside the 100 ms window
        clock.advance(by: .milliseconds(100))
        #expect(await eventually { model.rows.first?.state == .review })
    }

    @Test func aQuietPeriodLetsTheNextUpdateThroughImmediately() async throws {
        let clock = ManualClock()
        let (model, _) = try makeModel(clock: clock)
        let id = UUID()
        model.receive(PreviewFixtures.task("T", state: .plan, id: id))
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(100))
        await settle()
        model.receive(PreviewFixtures.task("T", state: .code, id: id))
        #expect(model.rows.first?.state == .code)
    }

    // MARK: peek

    @Test func peekIsSetOncePerStateChange() throws {
        let (model, _) = try makeModel(clock: ManualClock())
        let id = UUID()
        model.receive(PreviewFixtures.task("Plan me", state: .awaitingApproval, id: id))
        let first = model.peek
        #expect(first?.kind == .planReady && first?.taskID == id)
        model.receive(PreviewFixtures.task("Plan me", state: .awaitingApproval, id: id, tokens: 10))
        #expect(model.peek == first)
    }

    @Test func peekIsSuppressedWhenAlertsAreOff() throws {
        let (model, _) = try makeModel(clock: ManualClock())
        model.showAlerts = false
        model.receive(PreviewFixtures.task(state: .failed))
        #expect(model.peek == nil)
    }

    @Test func donePeekSaysHowManyFindingsTheSavedReviewHas() async throws {
        let report = ReviewReport.parse("[HIGH] a.swift:1 - one\n[LOW] b.swift:2 - two")
        let (model, _) = try makeModel(clock: ManualClock(), reviewLoader: StubReviewLoader(report: report))
        model.receive(PreviewFixtures.task("Login", state: .done, reviewFile: URL(fileURLWithPath: "/tmp/MyApp/r.md")))
        #expect(await eventually { model.peek?.kind == .done })
        #expect(model.peek?.text == "Login: done, \(report.findings.count) findings")
    }

    @Test func donePeekStaysPlainWhenTheReviewCannotBeLoaded() async throws {
        let (model, _) = try makeModel(clock: ManualClock(), reviewLoader: StubReviewLoader(report: nil))
        model.receive(PreviewFixtures.task("Login", state: .done, reviewFile: URL(fileURLWithPath: "/tmp/MyApp/r.md")))
        #expect(await eventually { model.peek?.kind == .done })
        #expect(model.peek?.text == "Login: done")
    }

    @Test func summaryAndClearDoneFollowTheTasks() throws {
        let (model, _) = try makeModel(clock: ManualClock())
        model.receive(PreviewFixtures.task("a", state: .code))
        model.receive(PreviewFixtures.task("b", state: .done))
        #expect(model.summary.activeCount == 1)
        model.clearDone()
        #expect(model.rows.map(\.title) == ["a"])
    }

    // MARK: engine integration

    @Test func engineRunReachesTheRowsAndActionsRoundTrip() async throws {
        let h = try Harness(recording: false)
        let (model, _) = try makeModel(harness: h)
        model.start()
        await model.submit(h.draft(title: "Add login"))
        #expect(await eventually { model.rows.first?.state == .awaitingApproval })
        #expect(model.peek?.kind == .planReady)
        let id = try #require(model.rows.first?.id)
        _ = await model.approve(id)
        #expect(await eventually { model.rows.first?.state == .done })
        #expect(model.lastError == nil)
        #expect(await eventually { model.peek?.kind == .done })
        #expect(model.todayTokens >= 0)
        model.stop()
    }

    @Test func startAfterStopReceivesUpdatesAgain() async throws {
        let h = try Harness(recording: false)
        let (model, _) = try makeModel(harness: h)
        model.start()
        await model.submit(h.draft(title: "First start"))
        #expect(await eventually { model.rows.count == 1 })
        model.stop()
        model.start()
        await model.submit(h.draft(title: "Second start"))
        #expect(await eventually { model.rows.count == 2 })
        model.stop()
    }

    @Test func failedActionsSurfaceAnError() async throws {
        let (model, _) = try makeModel()
        #expect(await model.approve(UUID()) == false)
        #expect(model.lastError != nil)
    }

    @Test func cancelStopsARunningTask() async throws {
        let h = try Harness(recording: false)
        let (model, _) = try makeModel(harness: h)
        model.start()
        await model.submit(h.draft())
        #expect(await eventually { model.rows.first?.state == .awaitingApproval })
        let id = try #require(model.rows.first?.id)
        await model.cancel(id)
        #expect(await eventually { model.rows.first?.state == .cancelled })
        model.stop()
    }

    // MARK: logs

    @Test func logLinesComeFromTheStoreAndBumpTheRevision() async throws {
        let logs = TaskLogStore()
        let (model, _) = try makeModel(logs: logs)
        model.start()
        let id = UUID()
        await logs.append("hello\nworld", stage: .code, to: id)
        #expect(await model.log(for: id).map(\.text) == ["hello", "world"])
        #expect(await eventually { model.logRevision > 0 })
        model.stop()
    }
}
