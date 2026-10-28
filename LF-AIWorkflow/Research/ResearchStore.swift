//
//  ResearchStore.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct ResearchFolder: Sendable, Equatable {
    let url: URL
}

nonisolated struct ResearchSource: Sendable, Equatable {
    let url: String
    let title: String
    let body: String
}

nonisolated enum ResearchStoreError: Error, Equatable {
    case outsideRoot
    case symlinkRefused(String)
    case ioFailed(String)
}

/// Owns the on-disk research folder layout. Every write is atomic, confined to one folder, 0o600 files / 0o700 dirs.
actor ResearchStore {
    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL) { self.root = root }

    /// Creates `<yyyy-MM-dd>-<slug>` (suffix `-2`, `-3` on collision).
    /// Complexity: O(c) time (c = existing collisions), O(1) space
    func createFolder(question: String, date: Date) throws -> ResearchFolder {
        try makeDirectory(root)
        let base = "\(Self.dayString(date))-\(Slug.make(question))"
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base)-\(n)"
            let url = root.appendingPathComponent(name, isDirectory: true)
            if !exists(url) {
                try makeDirectory(url)
                return ResearchFolder(url: url)
            }
            n += 1
        }
    }

    /// Complexity: O(n) time, O(n) space (n = body size)
    func writeSource(_ source: ResearchSource, index: Int, in folder: ResearchFolder) throws -> URL {
        let text = "---\nurl: \(Slug.yamlQuoted(source.url))\ntitle: \(Slug.yamlQuoted(source.title))\n---\n\(source.body)\n"
        let name = Self.indexed(index, Slug.make(source.title)) + ".md"
        return try write(Data(text.utf8), name: name, subdir: "sources", in: folder)
    }

    /// Writes `tables/<NN>-<k>.csv` (NN = source number, k = table index).
    /// Complexity: O(cells) time, O(cells) space
    func writeTable(_ rows: [[String]], source: Int, index: Int, in folder: ResearchFolder) throws -> URL {
        let name = String(format: "%02d-%d.csv", max(0, source), max(0, index))
        return try write(Data(CSVWriter.document(rows).utf8), name: name, subdir: "tables", in: folder)
    }

    /// Complexity: O(n) time, O(n) space
    func writeReport(_ markdown: String, in folder: ResearchFolder) throws -> URL {
        try write(Data(markdown.utf8), name: "report.md", subdir: nil, in: folder)
    }

    /// Complexity: O(total cells) time, O(same) space
    func writeComparisonCSV(_ rows: [[String]], in folder: ResearchFolder) throws -> URL {
        try write(Data(CSVWriter.document(rows).utf8), name: "comparison.csv", subdir: nil, in: folder)
    }

    // MARK: - Private

    private static func indexed(_ index: Int, _ slug: String) -> String {
        String(format: "%02d-%@", max(0, index), slug)
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func exists(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func makeDirectory(_ url: URL) throws {
        if isSymlink(url) { throw ResearchStoreError.symlinkRefused(url.lastPathComponent) }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { throw ResearchStoreError.ioFailed(String(describing: error)) }
    }

    private func write(_ data: Data, name: String, subdir: String?, in folder: ResearchFolder) throws -> URL {
        let rootPath = root.resolvingSymlinksInPath().path
        let folderResolved = folder.url.resolvingSymlinksInPath()
        guard folderResolved.deletingLastPathComponent().path == rootPath else { throw ResearchStoreError.outsideRoot }
        var dir = folderResolved
        if let subdir {
            dir = folderResolved.appendingPathComponent(subdir, isDirectory: true)
            try makeDirectory(dir)
            guard dir.resolvingSymlinksInPath().path == dir.path else { throw ResearchStoreError.symlinkRefused(subdir) }
        }
        let target = dir.appendingPathComponent(name)
        if isSymlink(target) { throw ResearchStoreError.symlinkRefused(name) }
        do {
            try data.write(to: target, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch { throw ResearchStoreError.ioFailed(String(describing: error)) }
        return target
    }
}
