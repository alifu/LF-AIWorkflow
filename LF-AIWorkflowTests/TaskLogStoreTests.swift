//
//  TaskLogStoreTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct TaskLogStoreTests {
    @Test func keepsOrderAndAssignsIncreasingIds() async {
        let store = TaskLogStore()
        let id = UUID()
        await store.append("a", stage: .plan, to: id)
        await store.append("b", stage: .code, to: id)
        let lines = await store.lines(for: id)
        #expect(lines.map(\.text) == ["a", "b"])
        #expect(lines.map(\.stage) == [.plan, .code])
        #expect(lines[0].id < lines[1].id)
    }

    @Test func dropsOldestAtCapacity() async {
        let store = TaskLogStore(capacityPerTask: 3)
        let id = UUID()
        for i in 1...5 { await store.append("l\(i)", stage: .code, to: id) }
        let lines = await store.lines(for: id)
        #expect(lines.map(\.text) == ["l3", "l4", "l5"])
    }

    @Test func tasksAreIsolated() async {
        let store = TaskLogStore(capacityPerTask: 2)
        let a = UUID(), b = UUID()
        await store.append("a1", stage: .plan, to: a)
        await store.append("b1", stage: .plan, to: b)
        await store.append("a2", stage: .plan, to: a)
        await store.append("a3", stage: .plan, to: a)
        #expect(await store.lines(for: a).map(\.text) == ["a2", "a3"])
        #expect(await store.lines(for: b).map(\.text) == ["b1"])
        #expect(await store.lines(for: UUID()).isEmpty)
    }

    @Test func stripsAnsiAndSkipsEmptyLines() async {
        let store = TaskLogStore()
        let id = UUID()
        await store.append("\u{1B}[31mred\u{1B}[0m", stage: .test, to: id)
        await store.append("\u{1B}[2K", stage: .test, to: id)
        #expect(await store.lines(for: id).map(\.text) == ["red"])
    }

    @Test func publishesChangedTaskId() async {
        let store = TaskLogStore()
        let id = UUID()
        var iterator = store.changes.makeAsyncIterator()
        await store.append("x", stage: .plan, to: id)
        #expect(await iterator.next() == id)
    }

    @Test func tailReturnsLastNLinesAndRevision() async {
        let store = TaskLogStore()
        let id = UUID()
        for i in 1...5 { await store.append("l\(i)", stage: .code, to: id) }
        let snap = await store.tail(for: id, limit: 2)
        #expect(snap.lines.map(\.text) == ["l4", "l5"])
        #expect(snap.revision == 5)
        await store.append("l6", stage: .code, to: id)
        #expect(await store.tail(for: id, limit: 2).revision == 6)
        #expect(await store.tail(for: UUID(), limit: 2) == TaskLogSnapshot(lines: [], revision: 0))
        #expect(await store.tail(for: id, limit: 0).lines.isEmpty)
    }
}
