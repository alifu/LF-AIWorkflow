//
//  SettingsValidation.swift
//  LF-AIWorkflow
//
//  Pure validation for Settings input. Nothing here runs a process; CLI paths reach argv only after this passes.

import Foundation

/// Allowed ranges for numeric settings. Stored values outside a range are clamped on load and on every write.
nonisolated enum SettingsLimits {
    static let maxTurns = 1...200
    /// Zero would pause every task at once, so the per-task budget starts at 1 token.
    static let taskTokens = 1...10_000_000
    /// 0 means no daily cap.
    static let dayTokens = 0...100_000_000
    static let promptTokens = 500...100_000
}

nonisolated enum ClampOutcome: Sendable, Equatable {
    /// `message` is non-nil when the typed value had to change; the UI shows it next to the field.
    case value(Int, message: String?)
    case invalid(String)
}

nonisolated enum SettingsValidation {
    /// Complexity: O(1) time, O(1) space
    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Parses typed text as a whole number and clamps it into `range`.
    /// Complexity: O(n) time, O(1) space (n = text length)
    static func parse(_ text: String, range: ClosedRange<Int>, label: String) -> ClampOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let number = Int(trimmed) else { return .invalid("\(label) must be a whole number.") }
        let clamped = clamp(number, to: range)
        guard clamped != number else { return .value(clamped, message: nil) }
        return .value(clamped, message: "\(label) must be between \(range.lowerBound) and \(range.upperBound); using \(clamped).")
    }

    /// Complexity: O(k) time, O(1) space (k = known models)
    static func isKnownModel(_ name: String) -> Bool {
        KnownModels.all.contains(name)
    }
}

/// What the file system holds at a path, as far as a CLI override cares.
nonisolated enum ToolFileKind: Sendable, Equatable {
    case missing, notRegularFile, notExecutable, regularExecutable
}

nonisolated enum ToolPathError: Error, Sendable, Equatable {
    case empty, notAbsolute, invalidCharacters, missing, notRegularFile, notExecutable

    var message: String {
        switch self {
        case .empty: "Enter a path or choose the file."
        case .notAbsolute: "The path must start with / (an absolute path)."
        case .invalidCharacters: "The path contains control characters."
        case .missing: "No file exists at this path."
        case .notRegularFile: "The path is a folder or other item, not an executable file."
        case .notExecutable: "The file is not executable."
        }
    }
}

nonisolated enum ToolPathValidator {
    /// Trims, checks the text's shape, then asks `kind` about the file. Only an absolute, existing, executable
    /// regular file passes. The returned path is the symlink-resolved path, so what is checked is what gets launched.
    /// Complexity: O(n + p) time, O(n) space (n = path length, p = path components); `kind` adds one stat-style call
    static func validate(
        _ raw: String, resolve: (String) -> String = ToolPathValidator.resolvingSymlinks(_:),
        kind: (String) -> ToolFileKind) -> Result<String, ToolPathError> {
        let typed = raw.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return .failure(.empty) }
        guard typed.hasPrefix("/") else { return .failure(.notAbsolute) }
        guard !typed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
        let path = resolve(typed)
        switch kind(path) {
        case .missing: return .failure(.missing)
        case .notRegularFile: return .failure(.notRegularFile)
        case .notExecutable: return .failure(.notExecutable)
        case .regularExecutable: return .success(path)
        }
    }

    /// Complexity: O(p) time, O(p) space (p = path components)
    static func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Real file system probe. Symlinks are resolved, so an alias to an executable counts; directories do not.
    /// Complexity: O(p) time, O(1) space (p = path components)
    static func kind(atPath path: String) -> ToolFileKind {
        let manager = FileManager.default
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: resolved, isDirectory: &isDirectory) else { return .missing }
        let type = (try? manager.attributesOfItem(atPath: resolved)[.type] as? FileAttributeType) ?? nil
        guard !isDirectory.boolValue, type == .typeRegular else { return .notRegularFile }
        return manager.isExecutableFile(atPath: resolved) ? .regularExecutable : .notExecutable
    }
}
