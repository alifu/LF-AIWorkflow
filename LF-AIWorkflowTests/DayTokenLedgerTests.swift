//
//  DayTokenLedgerTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

struct DayTokenLedgerTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2026-03-10 23:00 UTC.
    private static let evening = Date(timeIntervalSince1970: 1_773_183_600)

    @Test func addAccumulatesAndIgnoresNonPositive() async {
        let ledger = DayTokenLedger(fileURL: nil, calendar: Self.calendar, now: { Self.evening })
        await ledger.add(100); await ledger.add(50); await ledger.add(0); await ledger.add(-5)
        #expect(await ledger.used() == 150)
    }

    @Test func totalResetsAtMidnight() async {
        let clock = Clock(Self.evening)
        let ledger = DayTokenLedger(fileURL: nil, calendar: Self.calendar, now: { clock.now })
        await ledger.add(400)
        clock.advance(30 * 60)
        #expect(await ledger.used() == 400)
        clock.advance(60 * 60)
        #expect(await ledger.used() == 0)
        await ledger.add(7)
        #expect(await ledger.used() == 7)
    }

    @Test func persistsAndReloadsSameDayOnly() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sub/day.json")
        let first = DayTokenLedger(fileURL: file, calendar: Self.calendar, now: { Self.evening })
        await first.add(321)
        let same = DayTokenLedger(fileURL: file, calendar: Self.calendar, now: { Self.evening })
        #expect(await same.used() == 321)
        let nextDay = DayTokenLedger(fileURL: file, calendar: Self.calendar, now: { Self.evening.addingTimeInterval(2 * 3600) })
        #expect(await nextDay.used() == 0)
    }

    @Test func corruptFileStartsAtZero() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("day.json")
        try Data("not json".utf8).write(to: file)
        let ledger = DayTokenLedger(fileURL: file, calendar: Self.calendar, now: { Self.evening })
        #expect(await ledger.used() == 0)
    }
}
