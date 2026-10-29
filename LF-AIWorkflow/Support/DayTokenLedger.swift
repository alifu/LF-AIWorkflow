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

    private let fileURL: URL?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var day: String
    private var tokens: Int

    /// A nil `fileURL` keeps the ledger in memory only.
    /// Complexity: O(1) time, O(1) space
    init(fileURL: URL?, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        let today = Self.dayKey(now(), calendar)
        day = today
        tokens = 0
        if let fileURL, let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data),
           stored.day == today, stored.tokens > 0 {
            tokens = stored.tokens
        }
    }

    /// Tokens recorded for the current calendar day.
    /// Complexity: O(1) time, O(1) space
    func used() -> Int {
        rollOverIfNeeded()
        return tokens
    }

    /// Adds spend to today's total and persists it. Non-positive amounts are ignored.
    /// Complexity: O(1) time, O(1) space
    func add(_ amount: Int) {
        guard amount > 0 else { return }
        rollOverIfNeeded()
        let (sum, overflow) = tokens.addingReportingOverflow(amount)
        tokens = overflow ? Int.max : sum
        persist()
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
