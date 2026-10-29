//
//  EngineSettingsSnapshotTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct EngineSettingsSnapshotTests {
    private func storeWith(_ configure: (SettingsStore) -> Void) -> SettingsStore {
        let store = SettingsStore(suiteName: "lf-engine-snapshot-\(UUID().uuidString)")
        configure(store)
        return store
    }

    @Test func stageOverridesReachThePolicy() {
        let store = storeWith {
            $0.stageModels = [.code: "haiku"]
            $0.stageMaxTurns = [.plan: 3]
        }
        let settings = EngineSettings.from(store.snapshot())
        #expect(settings.policy.config(for: .code).model == "haiku")
        #expect(settings.policy.config(for: .plan).maxTurns == 3)
        #expect(settings.policy.config(for: .plan).model == "opus")
        #expect(settings.policy.config(for: .review).maxTurns == 8)
    }

    @Test func budgetsReachTheEngineBudget() {
        let store = storeWith {
            $0.taskBudget = 50_000
            $0.promptCaps = [.review: 9_000]
        }
        let budget = EngineSettings.from(store.snapshot()).budget
        #expect(budget.perTaskMaxTokens == 50_000)
        #expect(budget.promptCap(for: .review) == 9_000)
        #expect(budget.promptCap(for: .code) == TokenBudget.default.promptCap(for: .code))
    }

    @Test func defaultsMatchTheEngineDefaults() {
        let settings = EngineSettings.from(storeWith { _ in }.snapshot())
        #expect(settings.policy == EngineSettings.default.policy)
        #expect(settings.budget == TokenBudget.default)
        #expect(settings.fixLoopCap == EngineSettings.default.fixLoopCap)
    }

    @Test func taskStartedBeforeAChangeKeepsItsSettings() async throws {
        let h = try Harness()
        let id = try await h.runToCodeStart()

        let store = storeWith { $0.stageModels = [.code: "haiku"] }
        await h.engine.update(settings: EngineSettings.from(store.snapshot()))

        #expect(await h.recorder.wait(.done))
        #expect(h.claude.calls(for: .code).first?.config.model == "sonnet")
        #expect(await h.engine.effectiveSettings(for: id) == EngineSettings.from(store.snapshot()))  // snapshot pruned at done (TD-071)
    }

    @Test func taskSubmittedAfterAChangeUsesTheNewSettings() async throws {
        let h = try Harness()
        let store = storeWith { $0.stageModels = [.plan: "haiku"] }
        await h.engine.update(settings: EngineSettings.from(store.snapshot()))

        let id = await h.engine.submit(h.draft())
        #expect(await h.recorder.wait(.awaitingApproval))
        #expect(h.claude.calls(for: .plan).last?.config.model == "haiku")
        #expect(await h.engine.effectiveSettings(for: id).policy.config(for: .plan).model == "haiku")
    }
}
