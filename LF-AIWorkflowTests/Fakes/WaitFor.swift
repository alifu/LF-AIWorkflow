//
//  WaitFor.swift
//  LF-AIWorkflowTests
//

import Foundation

/// Thrown when `waitUntil` runs out of budget; names the condition so a red run is diagnosable.
struct WaitTimeout: Error, CustomStringConvertible {
    let condition: String
    let budget: Duration
    var description: String { "timed out after \(budget) waiting for: \(condition)" }
}

/// Default budget for polled waits. Raised from 5 s (TD-121): the full suite stalls some waits under load.
let defaultWaitBudget: Duration = .seconds(20)

/// Polls `check` every `interval` until it returns true or `budget` elapses.
/// Complexity: O(budget / interval) time, O(1) space
func waitUntil(_ condition: String, budget: Duration = defaultWaitBudget, interval: Duration = .milliseconds(5),
               _ check: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: budget)
    while ContinuousClock.now < deadline {
        if await check() { return }
        try await Task.sleep(for: interval)
    }
    if await check() { return }
    throw WaitTimeout(condition: condition, budget: budget)
}
