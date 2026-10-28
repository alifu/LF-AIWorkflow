//
//  EditorOpener.swift
//  LF-AIWorkflow
//

import AppKit
import Foundation

/// Decides whether a model- or file-supplied path may be opened. Everything that is not provably inside `root` is refused.
nonisolated enum PathContainment {
    /// Resolves `path` (relative to `root`, or absolute) to an existing file inside `root`. Returns nil for an empty path,
    /// a NUL byte, a leading `-`, any `..` component, a missing file, or a target (after symlink resolution) outside `root`.
    /// Complexity: O(len) time, O(len) space (plus the filesystem calls to resolve symlinks)
    static func resolve(_ path: String, within root: URL) -> URL? {
        guard !path.contains("\0") else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return nil }
        guard !trimmed.split(separator: "/").contains("..") else { return nil }
        let candidate = trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed) : root.appendingPathComponent(trimmed)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard resolved.path.hasPrefix(prefix), FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }
}

/// What the app may do with a path that already passed containment.
nonisolated enum OpenSafety {
    /// Source, text and markup types that are safe to hand to the default app.
    static let allowedExtensions: Set<String> = [
        "swift", "c", "h", "m", "mm", "cpp", "hpp", "md", "markdown", "txt", "json", "yml", "yaml", "toml", "js", "ts", "tsx", "jsx",
        "py", "rb", "go", "rs", "kt", "kts", "java", "css", "xml", "plist", "strings", "gradle",
    ]

    /// True only for a regular (not symlink, directory, FIFO, device) file with no execute bit and an allowed extension.
    /// Uses `lstat`, so it never blocks and never follows a final symlink.
    /// Complexity: O(len) time, O(1) space
    static func isSafeToOpen(_ url: URL) -> Bool {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFREG && (info.st_mode & 0o111) == 0
    }
}

/// Opens a file with the user's default app. The only side effect is behind this seam so tests can spy on it.
@MainActor
protocol URLOpening {
    func open(_ url: URL) -> Bool
    func reveal(_ url: URL)
}

@MainActor
protocol EditorOpening {
    /// Opens `path` if it resolves inside `root` and is a safe file type; otherwise reveals it in Finder.
    /// Returns false when refused (escapes the root, missing) or when the open failed.
    /// `line` is best effort: the default opener does not jump to it.
    func open(path: String, line: Int?, within root: URL) -> Bool
    func reveal(_ url: URL)
}

/// Containment check, file-type check, then NSWorkspace. Never goes through a shell.
@MainActor
struct EditorOpener: EditorOpening {
    let backend: any URLOpening
    /// Test seam: runs between the first check and the final re-verification.
    let beforeOpen: @MainActor (URL) -> Void

    init(backend: any URLOpening = WorkspaceURLOpener(), beforeOpen: @escaping @MainActor (URL) -> Void = { _ in }) {
        self.backend = backend
        self.beforeOpen = beforeOpen
    }

    /// Complexity: O(len) time, O(len) space
    func open(path: String, line: Int?, within root: URL) -> Bool {
        guard let url = PathContainment.resolve(path, within: root) else { return false }
        guard OpenSafety.isSafeToOpen(url) else {
            backend.reveal(url)
            return true
        }
        beforeOpen(url)
        // Re-verify right before the call: the path must still resolve to the same place inside the root and still be safe.
        guard let again = PathContainment.resolve(url.path, within: root), again == url else { return false }
        guard OpenSafety.isSafeToOpen(again) else {
            backend.reveal(again)
            return true
        }
        return backend.open(again)
    }

    func reveal(_ url: URL) { backend.reveal(url) }
}

@MainActor
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
