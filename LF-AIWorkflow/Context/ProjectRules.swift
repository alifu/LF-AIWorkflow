//
//  ProjectRules.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct RulesFile: Sendable, Equatable {
    let url: URL
    let byteSize: UInt64
    let estimatedTokens: Int
    let isTooLarge: Bool
}

nonisolated enum RulesWarning: Sendable, Equatable {
    case missingRules, tooLarge(file: String, tokens: Int, limit: Int), unreadable(String)
}

nonisolated struct ProjectRulesReport: Sendable, Equatable {
    let rulesFiles: [RulesFile]
    let checklists: [URL]
    let warnings: [RulesWarning]
}

nonisolated enum ProjectRules {
    static let rulesNames = ["CLAUDE.md", "AGENTS.md"]
    static let readCapBytes = 64 * 1024

    /// Looks for rules files in `root` and `review/checklist-*.md` (no recursion). Reads at most `readCapBytes` per file.
    /// Complexity: O(f * readCapBytes + e log e) time, O(readCapBytes) space (f = rules files, e = entries in review/)
    static func scan(root: URL, rulesMaxTokens: Int) -> ProjectRulesReport {
        var files: [RulesFile] = []
        var warnings: [RulesWarning] = []
        var sawRulesFile = false
        for name in rulesNames {
            let url = root.appendingPathComponent(name)
            guard isRegularFile(url) else { continue }
            sawRulesFile = true
            do {
                let file = try inspect(url, rulesMaxTokens: rulesMaxTokens)
                files.append(file)
                if file.isTooLarge {
                    warnings.append(.tooLarge(file: name, tokens: file.estimatedTokens, limit: rulesMaxTokens))
                }
            } catch {
                warnings.append(.unreadable(name))
            }
        }
        if !sawRulesFile { warnings.append(.missingRules) }
        return ProjectRulesReport(rulesFiles: files, checklists: checklists(root: root), warnings: warnings)
    }

    /// First `readCapBytes` of the file (empty when unreadable).
    /// Complexity: O(readCapBytes) time, O(readCapBytes) space
    static func sampleBytes(of url: URL) -> Data {
        (try? readSample(url)) ?? Data()
    }

    private static func readSample(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: readCapBytes) ?? Data()
    }

    private static func inspect(_ url: URL, rulesMaxTokens: Int) throws -> RulesFile {
        let sample = try readSample(url)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value
            ?? UInt64(sample.count)
        var tokens = TokenEstimator.estimate(sample)
        if size > UInt64(sample.count), !sample.isEmpty {
            tokens = Int(min(UInt64(Int.max), UInt64(tokens) * size / UInt64(sample.count)))
        }
        let tooLarge = tokens > rulesMaxTokens || size > UInt64(readCapBytes)
        return RulesFile(url: url, byteSize: size, estimatedTokens: tokens, isTooLarge: tooLarge)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
    }

    private static func checklists(root: URL) -> [URL] {
        let dir = root.appendingPathComponent("review")
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("checklist-") && $0.pathExtension == "md" && isRegularFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
