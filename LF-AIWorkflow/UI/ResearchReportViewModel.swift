//
//  ResearchReportViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

/// Logic behind the research detail: preview exclusions, the parsed report, CSV export, follow-up and Open folder.
/// Everything shown comes from `ReportWriter`'s sanitized output; files are only revealed, never opened.
@MainActor @Observable
final class ResearchReportViewModel {
    private(set) var task: ResearchTask
    private(set) var report: ResearchReport?
    private(set) var excluded: Set<Int> = []
    var followUpText = ""

    @ObservationIgnored private let controller: any ResearchControlling
    @ObservationIgnored private let opener: any EditorOpening
    @ObservationIgnored private let readReport: @Sendable (URL) async -> String?

    nonisolated static let maxReportBytes = 2_000_000

    init(task: ResearchTask, controller: any ResearchControlling, opener: any EditorOpening = EditorOpener(),
         readReport: @escaping @Sendable (URL) async -> String? = ResearchReportViewModel.readFile) {
        self.task = task
        self.controller = controller
        self.opener = opener
        self.readReport = readReport
    }

    func update(_ new: ResearchTask) { task = new }

    var isRunning: Bool { [.queued, .capture, .clean, .extract, .analyze, .report].contains(task.state) }
    var canAsk: Bool { task.state == .done && !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var table: ComparisonTable? { report?.table }

    // MARK: - Preview

    /// Flips a source (1-based preview number) in or out of the send set.
    func toggle(_ index: Int) {
        if excluded.contains(index) { excluded.remove(index) } else { excluded.insert(index) }
    }

    func sendSelected() async { await controller.send(task.id, excluded: excluded) }
    func cancel() async { await controller.cancel(task.id) }

    // MARK: - Report

    /// Complexity: O(report size) time, O(report size) space
    func loadReport() async {
        guard let file = task.reportFile, let text = await readReport(file) else { report = nil; return }
        report = ReportWriter.parse(text, sourceCount: Int.max / 2)
    }

    /// Complexity: O(cells) time, O(cells) space
    func csvDocument() -> String? {
        table.map { CSVWriter.document($0.csvRows) }
    }

    /// Complexity: O(cells) time, O(cells) space
    func exportCSV(to url: URL) throws {
        guard let csv = csvDocument() else { return }
        try Data(csv.utf8).write(to: url, options: .atomic)
    }

    func ask() async {
        guard canAsk else { return }
        let question = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        followUpText = ""
        await controller.followUp(task.id, question: question)
    }

    /// Reveals the task's own research folder in Finder (never opens a file, never takes a path from the model).
    @discardableResult
    func openFolder() -> Bool {
        guard let url = task.folder?.url else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        opener.reveal(url)
        return true
    }

    /// Host to show in the confirmation before a link opens; nil for anything but http(s).
    static func confirmationHost(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url.host?.lowercased()
    }

    nonisolated static func readFile(_ url: URL) async -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxReportBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
