//
//  ToolLocator.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum Tool: String, Sendable, CaseIterable {
    case claude, graphify, git

    var displayName: String {
        switch self {
        case .claude: "Claude Code CLI"
        case .graphify: "graphify"
        case .git: "git"
        }
    }
}

nonisolated enum ToolLocatorError: Error, Sendable, Equatable, LocalizedError {
    case notFound(Tool, searched: [String])
    case overrideNotExecutable(Tool, path: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let tool, _):
            "\(tool.displayName) not found. Install it, or set its path in Settings › Tools."
        case .overrideNotExecutable(let tool, let path):
            "The configured \(tool.displayName) path is not an executable file: \(path). Fix it in Settings › Tools."
        }
    }
}

/// Finds CLI tools. A pure value: the login-shell PATH is resolved separately by `LoginShellPath`.
nonisolated struct ToolLocator: Sendable {
    private let searchDirectories: [String]
    private let overrides: [Tool: String]
    private let isExecutable: @Sendable (String) -> Bool

    init(searchPath: [String], overrides: [Tool: String] = [:],
         isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.searchDirectories = searchPath
        self.overrides = overrides
        self.isExecutable = isExecutable
    }

    /// An override wins and never falls back when invalid; otherwise the first search directory holding an executable.
    /// Complexity: O(d) time, O(1) space (d = search directories)
    func locate(_ tool: Tool) throws(ToolLocatorError) -> URL {
        if let path = overrides[tool] {
            guard path.hasPrefix("/"), isExecutable(path) else {
                throw .overrideNotExecutable(tool, path: path)
            }
            return URL(fileURLWithPath: path)
        }
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent(tool.rawValue)
            if isExecutable(candidate) { return URL(fileURLWithPath: candidate) }
        }
        throw .notFound(tool, searched: searchDirectories)
    }

    /// Order: login shell PATH, process PATH, common install dirs. Absolute entries only, deduplicated, `~` expanded.
    /// Complexity: O(n) time, O(n) space
    static func searchPath(loginShellPATH: String?, processPATH: String?, home: String) -> [String] {
        let fallbacks = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", "/usr/bin", "/bin"]
        let raw = [loginShellPATH, processPATH].compactMap { $0 }.flatMap { $0.split(separator: ":", omittingEmptySubsequences: true).map(String.init) }
            + fallbacks
        var seen = Set<String>()
        var result: [String] = []
        for entry in raw {
            let expanded = entry == "~" ? home : (entry.hasPrefix("~/") ? home + entry.dropFirst() : entry)
            guard expanded.hasPrefix("/"), seen.insert(expanded).inserted else { continue }
            result.append(expanded)
        }
        return result
    }
}
