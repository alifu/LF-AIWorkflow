//
//  DayTokenLedger.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Tokens spent today across all tasks, persisted as JSON so the daily cap survives a restart.
/// Only the current day is kept: the first read or write on a new calendar day starts again from zero.
actor DayTokenLedger {
    private struct Stored: Codable { let day: String; let tokens: Int }

    /// Outcome of `reserve`: the tokens were added to today's total, or the cap would be passed.
    enum Reservation: Sendable, Equatable {
        case granted
        case denied(spent: Int)
    }

    private let fileURL: URL?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let readFile: @Sendable (URL) -> Data?
    private var day: String
    private var tokens: Int
    private var isLoaded = false

    /// A nil `fileURL` keeps the ledger in memory only. The file is read lazily on first use, inside the actor.
    /// Complexity: O(1) time, O(1) space
    init(fileURL: URL?, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() },
         readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        self.readFile = readFile
        day = Self.dayKey(now(), calendar)
        tokens = 0
    }

    /// Tokens recorded for the current calendar day.
    /// Complexity: O(1) time, O(1) space (first call also reads the file once)
    func used() -> Int {
        prepare()
        return tokens
    }

    /// Adds spend to today's total and persists it. Non-positive amounts are ignored.
    /// Complexity: O(1) time, O(1) space
    func add(_ amount: Int) {
        guard amount > 0 else { return }
        prepare()
        credit(amount)
        persist()
    }

    /// Atomically checks `used + tokens <= limit` and, if it fits, counts `tokens` as spent.
    /// Complexity: O(1) time, O(1) space
    func reserve(_ amount: Int, limit: Int) -> Reservation {
        prepare()
        let spent = tokens
        let (sum, overflow) = spent.addingReportingOverflow(max(0, amount))
        guard !overflow, sum <= limit else { return .denied(spent: spent) }
        credit(amount)
        persist()
        return .granted
    }

    /// Replaces a reservation with the real spend: refunds the difference or charges the excess.
    /// Complexity: O(1) time, O(1) space
    func settle(reserved: Int, actual: Int) {
        prepare()
        let delta = max(0, actual) - max(0, reserved)
        if delta >= 0 { credit(delta) } else { tokens = max(0, tokens + delta) }
        persist()
    }

    private func credit(_ amount: Int) {
        let (sum, overflow) = tokens.addingReportingOverflow(amount)
        tokens = overflow ? Int.max : sum
    }

    /// Loads the stored total once, then rolls over on a new day.
    private func prepare() {
        if !isLoaded {
            isLoaded = true
            if let fileURL, let data = readFile(fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data),
               stored.day == day, stored.tokens > 0 {
                tokens = stored.tokens
            }
        }
        rollOverIfNeeded()
    }

    private func rollOverIfNeeded() {
        let today = Self.dayKey(now(), calendar)
        guard today != day else { return }
        day = today
        tokens = 0
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(Stored(day: day, tokens: tokens))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.workflow.warning("cannot save the daily token ledger: \(error.localizedDescription)")
        }
    }

    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
