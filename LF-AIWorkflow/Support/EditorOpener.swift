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
    /// Opens `url` with the app of `bundleIdentifier`, or the type's default app when nil or the app is not installed.
    func open(_ url: URL, bundleIdentifier: String?) -> Bool
    func reveal(_ url: URL)
}

@MainActor
protocol EditorOpening {
    /// Opens `path` if it resolves inside `root` and is a safe file type; otherwise reveals it in Finder.
    /// Returns false when refused (escapes the root, missing) or when the open failed.
    /// `line` is best effort: only Xcode (`xed --line`) and VS Code (`code -g`) jump to it.
    func open(path: String, line: Int?, within root: URL) -> Bool
    func reveal(_ url: URL)
}

/// Containment check, file-type check, then NSWorkspace. Never goes through a shell.
@MainActor
struct EditorOpener: EditorOpening {
    let backend: any URLOpening
    /// The editor picked in Settings, read at open time so a change applies at once.
    let choice: @MainActor () -> EditorChoice
    let jumper: any LineJumping
    /// Test seam: runs between the first check and the final re-verification.
    let beforeOpen: @MainActor (URL) -> Void

    init(backend: any URLOpening = WorkspaceURLOpener(),
         choice: @escaping @MainActor () -> EditorChoice = { EditorChoice.stored() },
         jumper: any LineJumping = CommandLineJumper(),
         beforeOpen: @escaping @MainActor (URL) -> Void = { _ in }) {
        self.backend = backend
        self.choice = choice
        self.jumper = jumper
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
        let editor = choice()
        if let line, let jump = editor.lineJump(path: again.path, line: line),
           jumper.jump(executable: jump.executable, arguments: jump.arguments) { return true }
        return backend.open(again, bundleIdentifier: editor.bundleIdentifier)
    }

    func reveal(_ url: URL) { backend.reveal(url) }
}

@MainActor
struct WorkspaceURLOpener: URLOpening {
    /// Complexity: O(1) time, O(1) space (LaunchServices does the work asynchronously)
    func open(_ url: URL, bundleIdentifier: String?) -> Bool {
        let workspace = NSWorkspace.shared
        guard let bundleIdentifier, let app = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return workspace.open(url)
        }
        workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

/// Spawns an editor's line-jump command. Side effect behind a seam so tests never launch an app.
@MainActor
protocol LineJumping {
    /// Returns false when the command cannot run (missing executable), so the caller can fall back to a plain open.
    func jump(executable: String, arguments: [String]) -> Bool
}

/// Runs the jump through `CommandRunner` (argv only, never a shell), fire and forget with a timeout.
@MainActor
struct CommandLineJumper: LineJumping {
    static let timeout: Duration = .seconds(10)

    /// Complexity: O(1) time, O(1) space
    func jump(executable: String, arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return false }
        let inv = ProcessInvocation(executable: URL(fileURLWithPath: executable), arguments: arguments, environment: [:],
                                    workingDirectory: URL(fileURLWithPath: "/"), stdin: Data())
        Task { _ = try? await CommandRunner.run(inv, timeout: Self.timeout) }
        return true
    }
}

extension EditorChoice {
    /// App to open files with; nil means the type's default app.
    nonisolated var bundleIdentifier: String? {
        switch self {
        case .systemDefault: nil
        case .xcode: "com.apple.dt.Xcode"
        case .vscode: "com.microsoft.VSCode"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .systemDefault: "System default"
        case .xcode: "Xcode"
        case .vscode: "Visual Studio Code"
        }
    }

    /// Executable and argv that open `path` at `line`; nil when the editor has no line option, `line` is below 1, or `path`
    /// is not absolute (so it can never read as an option).
    /// Complexity: O(len) time, O(len) space
    nonisolated func lineJump(path: String, line: Int) -> (executable: String, arguments: [String])? {
        guard line >= 1, path.hasPrefix("/") else { return nil }
        switch self {
        case .systemDefault: return nil
        case .xcode: return ("/usr/bin/xed", ["--line", String(line), path])
        case .vscode:
            return ("/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", ["-g", "\(path):\(line)"])
        }
    }

    /// The editor saved in Settings, read straight from defaults (for call sites that have no `SettingsStore`).
    /// Complexity: O(1) time, O(1) space
    @MainActor static func stored(suiteName: String? = nil) -> EditorChoice {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        return defaults.string(forKey: SettingsStore.Keys.editorChoice).flatMap(EditorChoice.init(rawValue:)) ?? .systemDefault
    }
}
