//
//  GraphifyClient.swift
//  LF-AIWorkflow
//

import Foundation
import os

/// Graph context via the `graphify` CLI. Optional by design: any failure yields `.empty`, never an error.
actor GraphifyClient: GraphQuerying {
    private let locator: ToolLocator
    private let queryTimeout: Duration
    private let updateTimeout: Duration
    private let environment: [String: String]
    /// One in-flight `graphify update` per root, shared by concurrent callers.
    private var updates: [URL: Task<Bool, Never>] = [:]

    init(locator: ToolLocator, queryTimeout: Duration = .seconds(20), updateTimeout: Duration = .seconds(180),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.locator = locator
        self.queryTimeout = queryTimeout
        self.updateTimeout = updateTimeout
        self.environment = environment
    }

    /// `graphify query "<q>" --budget N --graph <root>/graphify-out/graph.json`. A missing graph triggers one
    /// shared `update` first; if it still is missing the result is `.empty`.
    /// Complexity: O(output bytes) time, O(output bytes) space (plus the child's own work)
    func query(_ q: String, root: URL, budgetTokens: Int) async -> GraphContext {
        let graph = Self.graphURL(root)
        if !FileManager.default.fileExists(atPath: graph.path) {
            guard await refresh(root: root), FileManager.default.fileExists(atPath: graph.path) else { return .empty }
        }
        // The CLI has no `--` support, so a leading '-' would be parsed as an option: strip dashes and
        // whitespace alternately until neither remains.
        let question = String(q.drop(while: { $0 == "-" || $0.isWhitespace })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return .empty }
        let args = ["query", question, "--budget", String(max(1, budgetTokens)), "--graph", graph.path]
        guard let result = await exec(args, root: root, timeout: queryTimeout) else { return .empty }
        guard result.status == 0 else {
            AppLog.workflow.warning("graphify query exited \(result.status)")
            return .empty
        }
        let text = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return GraphContext(text: text, nodes: Self.parseNodes(text))
    }

    /// Re-extracts the graph; concurrent calls for one root share a single run. Failures are logged only.
    /// Complexity: O(1) time (plus the child's run), O(1) space
    func update(root: URL) async {
        _ = await refresh(root: root)
    }

    /// `NODE <label> [src=<file> loc=L<n> ...]` lines; other lines are ignored.
    /// Complexity: O(n) time, O(k) space (k = nodes)
    static func parseNodes(_ output: String) -> [GraphNode] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("NODE ") else { return nil }
            let body = line.dropFirst(5)
            guard let open = body.lastIndex(of: "["), body.last == "]" else {
                return GraphNode(label: String(body).trimmingCharacters(in: .whitespaces), file: nil, line: nil)
            }
            let label = body[..<open].trimmingCharacters(in: .whitespaces)
            let attributes = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            return GraphNode(label: label, file: attribute("src", in: attributes),
                             line: attribute("loc", in: attributes).flatMap { Int($0.drop { $0 == "L" }) })
        }
    }

    // MARK: - Private

    private static func graphURL(_ root: URL) -> URL {
        root.appendingPathComponent("graphify-out/graph.json")
    }

    /// Value of `key=` up to the next ` word=` attribute (values such as paths may contain spaces).
    private static func attribute(_ key: String, in attributes: String) -> String? {
        guard let start = attributes.range(of: key + "=") else { return nil }
        let rest = attributes[start.upperBound...]
        let end = rest.range(of: #" [A-Za-z_]+="#, options: .regularExpression)?.lowerBound ?? rest.endIndex
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }

    /// Runs (or joins) `graphify update <root>`; true on exit 0.
    private func refresh(root: URL) async -> Bool {
        if let running = updates[root] { return await running.value }
        let task = Task { [self] in await runUpdate(root: root) }
        updates[root] = task
        let ok = await task.value
        updates[root] = nil
        return ok
    }

    private func runUpdate(root: URL) async -> Bool {
        guard let result = await exec(["update", root.path], root: root, timeout: updateTimeout) else { return false }
        if result.status != 0 { AppLog.workflow.warning("graphify update exited \(result.status)") }
        return result.status == 0
    }

    private func exec(_ args: [String], root: URL, timeout: Duration) async -> CommandResult? {
        let executable: URL
        do { executable = try locator.locate(.graphify) } catch {
            AppLog.workflow.warning("graphify not available: \(String(describing: error))")
            return nil
        }
        let invocation = ProcessInvocation(executable: executable, arguments: args, environment: environment,
                                           workingDirectory: root, stdin: Data())
        do {
            return try await CommandRunner.run(invocation, timeout: timeout, maxOutputBytes: 1 << 20)
        } catch {
            AppLog.workflow.warning("graphify \(args.first ?? "") failed: \(String(describing: error))")
            return nil
        }
    }
}
