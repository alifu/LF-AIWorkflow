import Foundation

/// Writes plan and review files below a project root without following symlinked directories or files.
nonisolated enum SafeProjectFile {
    enum Failure: Error, Equatable { case symlinkedDirectory(String), notADirectory(String) }

    /// `<slug>-<first 8 hex of id>`: same-title tasks get distinct files.
    /// Complexity: O(1) time, O(1) space
    static func stem(slug: String, id: UUID) -> String {
        "\(slug)-\(id.uuidString.prefix(8).lowercased())"
    }

    /// Creates each component of `relativeDirectory` under `root` (refusing symlinks and non-directories),
    /// then writes `name` atomically (rename replaces a symlink at the target instead of following it).
    /// Complexity: O(d + size) time, O(size) space (d = path components)
    static func write(_ text: String, to relativeDirectory: String, name: String, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var dir = root
        for component in relativeDirectory.split(separator: "/") {
            dir = dir.appendingPathComponent(String(component), isDirectory: true)
            try ensureRealDirectory(dir)
        }
        let file = dir.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func ensureRealDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return
        }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: throw Failure.symlinkedDirectory(url.path)
        case S_IFDIR: return
        default: throw Failure.notADirectory(url.path)
        }
    }
}
