//
//  BoundedWaitTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(1)))
struct BoundedWaitTests {
    /// The operation may be a shared, deduped update that ignores cancellation (GraphifyClient.refresh):
    /// `run` must still return near the limit and not wait for it.
    @Test func returnsNearLimitWhenOperationIgnoresCancellation() async {
        let start = ContinuousClock.now
        await BoundedWait.run(limit: .milliseconds(100)) {
            _ = await Task { try? await Task.sleep(for: .seconds(4)) }.value
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func returnsEarlyWhenOperationFinishesFirst() async {
        let start = ContinuousClock.now
        await BoundedWait.run(limit: .seconds(20)) {}
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
