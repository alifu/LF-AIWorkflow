//
//  ToolsSettingsModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

/// Detection and version checks for the Tools tab. Detection and probing run off the main actor through the
/// injected closures; this type only holds the rows the view shows.
@MainActor
@Observable
final class ToolsSettingsModel {
    enum VersionState: Sendable, Equatable {
        case unchecked, checking
        case found(String)
        case failed(String)
    }

    struct Row: Sendable, Equatable, Identifiable {
        let tool: Tool
        /// Where ToolLocator found the tool; nil when it did not.
        let path: String?
        /// User-facing reason when the tool was not found or the override is broken.
        let problem: String?
        var version: VersionState = .unchecked

        var id: Tool { tool }
    }

    typealias Detect = @Sendable (Tool, [Tool: String]) async -> Result<URL, ToolLocatorError>
    typealias Probe = @Sendable (URL) async -> Result<String, ToolProbeError>

    private(set) var rows: [Row] = Tool.allCases.map { Row(tool: $0, path: nil, problem: nil) }
    private var locations: [Tool: URL] = [:]
    private let detect: Detect
    private let probe: Probe

    init(detect: @escaping Detect = ToolsSettingsModel.liveDetect,
         probe: @escaping Probe = { await ToolVersionProbe.run($0) }) {
        self.detect = detect
        self.probe = probe
    }

    /// The row for one tool after detection. Pure.
    /// Complexity: O(1) time, O(1) space
    static func row(for tool: Tool, located: Result<URL, ToolLocatorError>) -> Row {
        switch located {
        case .success(let url):
            Row(tool: tool, path: url.path, problem: nil)
        case .failure(let error):
            Row(tool: tool, path: nil, problem: error.errorDescription ?? "\(tool.displayName) not found.")
        }
    }

    /// Re-runs detection for every tool, using the override paths the user chose. Clears earlier version results.
    /// Complexity: O(t) detections (t = tools), each bounded by the locator's work
    func redetect(overrides: [Tool: String]) async {
        var found: [Tool: URL] = [:]
        var newRows: [Row] = []
        for tool in Tool.allCases {
            let located = await detect(tool, overrides)
            if case .success(let url) = located { found[tool] = url }
            newRows.append(Self.row(for: tool, located: located))
        }
        locations = found
        rows = newRows
    }

    /// Runs `--version` for one detected tool and stores the first line or the reason it failed.
    /// Does nothing for a tool without a detected path.
    /// Complexity: O(1) time plus the probe's process run (off the main actor)
    func test(_ tool: Tool) async {
        guard let url = locations[tool] else { return }
        setVersion(.checking, for: tool)
        let outcome = await probe(url)
        switch outcome {
        case .success(let line): setVersion(.found(line), for: tool)
        case .failure(let error): setVersion(.failed(error.message), for: tool)
        }
    }

    private func setVersion(_ state: VersionState, for tool: Tool) {
        rows = rows.map { row in
            guard row.tool == tool else { return row }
            var updated = row
            updated.version = state
            return updated
        }
    }

    /// Live detection: login-shell PATH, then `ToolLocator` with the user's overrides.
    /// Complexity: O(d) time over PATH entries plus the login-shell run
    nonisolated static func liveDetect(_ tool: Tool, overrides: [Tool: String]) async -> Result<URL, ToolLocatorError> {
        let searchPath = await AppComposition.resolveSearchPath()
        let locator = ToolLocator(searchPath: searchPath, overrides: overrides)
        do {
            return .success(try locator.locate(tool))
        } catch {
            return .failure(error)
        }
    }
}
