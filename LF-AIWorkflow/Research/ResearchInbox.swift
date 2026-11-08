//
//  ResearchInbox.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct InboxItem: Sendable, Equatable, Identifiable {
    let id: UUID
    let page: CapturedPage
}

nonisolated enum InboxResult: Sendable, Equatable {
    case added(count: Int)
    case addedDroppingOldest(count: Int, dropped: Int)
    case duplicate
}

/// Pages saved by the inbox hotkey, content captured at press time. Layout: `inbox/index.json` plus
/// `inbox/NN-<slug>.json`. Capped (oldest dropped); a corrupt index is renamed aside and restarted empty.
actor ResearchInbox {
    static let defaultCap = 100

    private struct Entry: Codable { let id: UUID; let key: String; let file: String }
    private struct Index: Codable { var next: Int; var entries: [Entry] }
    private struct PageDTO: Codable {
        let title: String, url: String, text: String
        let headings: [String], links: [String], tables: [[[String]]]
        let hasPasswordField: Bool
    }

    private let dir: URL
    private let cap: Int
    private let fileManager = FileManager.default
    private var index: Index?

    init(folder: URL, cap: Int = ResearchInbox.defaultCap) {
        self.dir = folder.appendingPathComponent("inbox", isDirectory: true)
        self.cap = max(1, cap)
    }

    /// Complexity: O(n) time (n = items), O(1) extra space
    func add(_ page: CapturedPage) throws -> InboxResult {
        var idx = try loadIndex()
        let key = (URLNormalizer.normalize(page.url.absoluteString) ?? page.url).absoluteString
        guard !idx.entries.contains(where: { $0.key == key }) else { return .duplicate }
        let file = String(format: "%02d-%@.json", idx.next, Slug.make(page.title.isEmpty ? key : page.title))
        let entry = Entry(id: UUID(), key: key, file: file)
        try write(Self.dto(page), to: dir.appendingPathComponent(file))
        idx.entries.append(entry)
        idx.next += 1
        var dropped = 0
        while idx.entries.count > cap {
            try? fileManager.removeItem(at: dir.appendingPathComponent(idx.entries.removeFirst().file))
            dropped += 1
        }
        try save(idx)
        return dropped == 0 ? .added(count: idx.entries.count)
                            : .addedDroppingOldest(count: idx.entries.count, dropped: dropped)
    }

    /// Complexity: O(n) time and space (n = items)
    func items() throws -> [InboxItem] {
        try loadIndex().entries.compactMap { entry in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(entry.file)),
                  let dto = try? JSONDecoder().decode(PageDTO.self, from: data),
                  let page = Self.page(dto) else { return nil }
            return InboxItem(id: entry.id, page: page)
        }
    }

    /// Complexity: O(n) time, O(1) extra space
    func remove(_ id: UUID) throws {
        var idx = try loadIndex()
        guard let at = idx.entries.firstIndex(where: { $0.id == id }) else { return }
        try? fileManager.removeItem(at: dir.appendingPathComponent(idx.entries[at].file))
        idx.entries.remove(at: at)
        try save(idx)
    }

    /// Returns every item and empties the inbox.
    /// Complexity: O(n) time and space
    func drain() throws -> [InboxItem] {
        let all = try items()
        for entry in try loadIndex().entries { try? fileManager.removeItem(at: dir.appendingPathComponent(entry.file)) }
        try save(Index(next: try loadIndex().next, entries: []))
        return all
    }

    // MARK: - Persistence

    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    private func loadIndex() throws -> Index {
        if let index { return index }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var loaded = Index(next: 1, entries: [])
        if let data = try? Data(contentsOf: indexURL) {
            if let decoded = try? JSONDecoder().decode(Index.self, from: data) {
                loaded = Index(next: decoded.next, entries: decoded.entries.filter { Self.isPlainFilename($0.file) })
            } else {
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                try? fileManager.moveItem(at: indexURL, to: dir.appendingPathComponent("index.json.corrupt-\(stamp)"))
            }
        }
        index = loaded
        return loaded
    }

    private func save(_ idx: Index) throws {
        try write(idx, to: indexURL)
        index = idx
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// An index entry may only name a file directly inside the inbox folder.
    /// Complexity: O(n) time, O(1) space (n = name length)
    static func isPlainFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    private static func dto(_ p: CapturedPage) -> PageDTO {
        PageDTO(title: p.title, url: p.url.absoluteString, text: p.text, headings: p.headings,
                links: p.links.map(\.absoluteString), tables: p.tables, hasPasswordField: p.hasPasswordField)
    }

    private static func page(_ d: PageDTO) -> CapturedPage? {
        guard let url = URLNormalizer.normalize(d.url) else { return nil }
        return CapturedPage(title: d.title, url: url, text: d.text, headings: d.headings,
                            links: d.links.compactMap { URLNormalizer.normalize($0) }, tables: d.tables,
                            hasPasswordField: d.hasPasswordField)
    }
}
