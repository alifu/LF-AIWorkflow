//
//  WaitForTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct WaitForTests {
    @Test func timeoutNamesTheAwaitedCondition() async {
        let error = await #expect(throws: WaitTimeout.self) {
            try await waitUntil("task reaches done", budget: .milliseconds(30), interval: .milliseconds(5)) { false }
        }
        #expect(error?.condition == "task reaches done")
        #expect(error?.description.contains("task reaches done") == true)
    }

    @Test func returnsOnceTheConditionHolds() async throws {
        let counter = Counter()
        try await waitUntil("third poll", budget: .seconds(2), interval: .milliseconds(1)) { await counter.next() >= 3 }
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
