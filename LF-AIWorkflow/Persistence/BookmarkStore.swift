//
//  BookmarkStore.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated struct ScopedBookmark: Sendable, Codable, Equatable {
    let url: URL
    let data: Data
}

nonisolated struct ResolvedBookmark: Sendable, Equatable {
    let url: URL
    let isStale: Bool
}

nonisolated struct SkillFolderLoad: Sendable, Equatable {
    let folders: [URL]
    /// Display paths of remembered folders that no longer resolve (deleted or moved); they are forgotten.
    let dropped: [String]
}

nonisolated protocol BookmarkStoring: Sendable {
    func makeBookmark(for url: URL) throws -> ScopedBookmark
    func resolve(_ bookmark: ScopedBookmark) throws -> ResolvedBookmark
    func loadSkillFolders(project: URL) -> SkillFolderLoad
    func saveSkillFolders(_ folders: [URL], project: URL)
}

/// Security-scoped bookmarks for skill folders, remembered per project in `UserDefaults`.
nonisolated struct BookmarkStore: BookmarkStoring {
    /// `UserDefaults` is not Sendable, so the suite name is kept and the (shared, thread-safe) defaults opened per call.
    let suiteName: String?
    static let keyPrefix = "composer.skillFolders."

    init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    static func key(for project: URL) -> String { keyPrefix + project.standardizedFileURL.path }

    /// Complexity: O(1) time, O(1) space (one filesystem call)
    func makeBookmark(for url: URL) throws -> ScopedBookmark {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return ScopedBookmark(url: url, data: data)
    }

    /// Throws when the target no longer exists. A stale result means the bookmark should be re-made from `url`.
    /// Complexity: O(1) time, O(1) space (one filesystem call)
    func resolve(_ bookmark: ScopedBookmark) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &isStale)
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    /// Resolves every remembered folder once. A stale bookmark is re-made and saved; one that cannot be resolved (or whose
    /// folder is gone) is dropped, reported in `dropped`, and forgotten.
    /// Complexity: O(k) time, O(k) space (k = remembered folders)
    func loadSkillFolders(project: URL) -> SkillFolderLoad {
        guard let data = defaults.data(forKey: Self.key(for: project)),
              let stored = try? JSONDecoder().decode([ScopedBookmark].self, from: data) else {
            return SkillFolderLoad(folders: [], dropped: [])
        }
        var kept: [ScopedBookmark] = []
        var dropped: [String] = []
        var changed = false
        for bookmark in stored {
            guard let resolved = try? resolve(bookmark), FileManager.default.fileExists(atPath: resolved.url.path) else {
                dropped.append(bookmark.url.path)
                changed = true
                continue
            }
            if resolved.isStale || resolved.url.path != bookmark.url.path {
                guard let fresh = try? makeBookmark(for: resolved.url) else { dropped.append(bookmark.url.path); changed = true; continue }
                kept.append(fresh)
                changed = true
            } else {
                kept.append(bookmark)
            }
        }
        if changed { write(kept, project: project) }
        return SkillFolderLoad(folders: kept.map(\.url), dropped: dropped)
    }

    /// Complexity: O(k) time, O(k) space
    func saveSkillFolders(_ folders: [URL], project: URL) {
        write(folders.compactMap { try? makeBookmark(for: $0) }, project: project)
    }

    private func write(_ bookmarks: [ScopedBookmark], project: URL) {
        let key = Self.key(for: project)
        guard !bookmarks.isEmpty, let data = try? JSONEncoder().encode(bookmarks) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
