//
//  WorkflowEngineDayBudgetTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(3)))
struct WorkflowEngineDayBudgetTests {
    private static func settings(day: Int) -> EngineSettings {
        var base = Harness.settings()
        base.dayBudget = day
        return base
    }

    @Test func stageParksWhenDayCapIsExceededThenResumesAfterRaisingIt() async throws {
        let ledger = DayTokenLedger(fileURL: nil)
        await ledger.add(1_000)
        let h = try Harness(settings: Self.settings(day: 500), ledger: ledger)
        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingInput))
        let parked = try #require(await h.engine.task(id))
        #expect(parked.waitReason == .dayBudgetExceeded(spent: 1_000, limit: 500))
        #expect(h.claude.calls.isEmpty)

        await h.engine.update(settings: Self.settings(day: 10_000_000))
        try await h.engine.resume(id)
        #expect(await h.recorder.wait(.awaitingApproval))
    }

    @Test func stageUsageIsAddedToTheLedger() async throws {
        let ledger = DayTokenLedger(fileURL: nil)
        let h = try Harness(settings: Self.settings(day: 10_000_000), ledger: ledger)
        h.claude.script(.plan, .outcome(FakeClaudeRunner.ok("p", tokens: 250)))
        _ = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(await ledger.used() == 250)
    }

    @Test func zeroCapMeansNoDailyLimit() async throws {
        let ledger = DayTokenLedger(fileURL: nil)
        await ledger.add(9_999_999)
        let h = try Harness(settings: Self.settings(day: 0), ledger: ledger)
        _ = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
    }
}
