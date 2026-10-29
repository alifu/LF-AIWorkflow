//
//  ResearchDayTotalTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

@MainActor
struct ResearchDayTotalTests {
    @Test func dayTotalReadsTheSharedLedgerSoCodeTaskTokensCount() async {
        let ledger = DayTokenLedger(fileURL: nil)
        await ledger.add(1_200)
        let hooks = AppComposition.researchDayHooks(ledger: ledger)
        #expect(await hooks.used() == 1_200)
    }

    @Test func researchSpendIsAddedToTheSameLedger() async {
        let ledger = DayTokenLedger(fileURL: nil)
        let hooks = AppComposition.researchDayHooks(ledger: ledger)
        await hooks.add(300)
        #expect(await ledger.used() == 300)
        #expect(await hooks.used() == 300)
    }

    @Test func noLedgerMeansZeroAndNoCrash() async {
        let hooks = AppComposition.researchDayHooks(ledger: nil)
        await hooks.add(10)
        #expect(await hooks.used() == 0)
    }

    @Test func researchRootRoundTripsThroughSettings() {
        let suite = "lf-root-\(UUID().uuidString)"
        SettingsStore(suiteName: suite).researchRootPath = "/tmp/lf-research"
        let reloaded = SettingsStore(suiteName: suite)
        #expect(reloaded.researchRootPath == "/tmp/lf-research")
        #expect(reloaded.researchRoot.path == "/tmp/lf-research")
    }

    @Test func rootValidatorAcceptsOnlyCleanAbsolutePaths() {
        #expect(ResearchRootValidator.validate("  /tmp/lf  ") == .success("/tmp/lf"))
        #expect(ResearchRootValidator.validate("") == .success(""))
        #expect(ResearchRootValidator.validate("relative/x") == .failure(.notAbsolute))
        #expect(ResearchRootValidator.validate("~/x") == .failure(.notAbsolute))
        #expect(ResearchRootValidator.validate("/tmp/a\nb") == .failure(.invalidCharacters))
        #expect(ResearchRootValidator.validate("/tmp/../etc") == .failure(.invalidCharacters))
    }

    @Test func inboxHotkeyChoicesExcludeTheMainShortcut() {
        let choices = HotkeySpec.inboxChoices(excluding: .controlOptionCommandC)
        #expect(!choices.contains(.controlOptionCommandC))
        #expect(!choices.isEmpty)
        #expect(choices.allSatisfy { $0.validate() == .valid })
    }
}
