//
//  ComposerAttachments.swift
//  LF-AIWorkflow
//

import Foundation

/// Limits and rules for what can be attached to a task.
nonisolated struct AttachmentPolicy: Sendable, Equatable {
    let maxDocuments: Int
    let maxDocumentBytes: Int
    let maxSkillFolders: Int
    /// Documents up to this many tokens count toward the estimate; larger ones are passed as paths only.
    let inlineMaxTokens: Int

    static let standard = AttachmentPolicy(maxDocuments: 10, maxDocumentBytes: 5 * 1024 * 1024,
                                           maxSkillFolders: 5, inlineMaxTokens: TokenBudget.default.inlineMaxTokens)

    private static let secretDirectories: Set<String> = [".ssh", ".aws", ".gnupg"]

    /// Checks both the lexical path and the symlink-resolved target, so `notes.txt -> ~/.ssh/id_rsa` is caught.
    /// Complexity: O(len) time, O(len) space (plus the filesystem calls to resolve symlinks)
    static func isSecret(url: URL) -> Bool {
        let lexical = url.standardizedFileURL
        return isSecretPath(lexical) || isSecretPath(lexical.resolvingSymlinksInPath())
    }

    private static func isSecretPath(_ url: URL) -> Bool {
        if isSecret(fileName: url.lastPathComponent) { return true }
        return url.pathComponents.dropLast().contains { secretDirectories.contains($0.lowercased()) }
    }

    /// `.env*`, `*.env`, `.npmrc`, `.netrc`, `.pypirc`, `.git-credentials`, `credentials*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`,
    /// `*.keystore`, `id_rsa*`, `id_ed25519*`, `id_ecdsa*` (case-insensitive).
    /// Complexity: O(len) time, O(len) space
    static func isSecret(fileName: String) -> Bool {
        let name = fileName.lowercased()
        if [".npmrc", ".netrc", ".pypirc", ".git-credentials"].contains(name) { return true }
        if name.hasPrefix(".env") || name.hasPrefix("credentials") { return true }
        if [".env", ".pem", ".key", ".p12", ".pfx", ".keystore"].contains(where: name.hasSuffix) { return true }
        return ["id_rsa", "id_ed25519", "id_ecdsa"].contains(where: name.hasPrefix)
    }
}

nonisolated enum DropRejection: Sendable, Equatable {
    case notFileURL, directory, notDirectory, missing, unreadable, duplicate
    case tooLarge(bytes: Int)
    case limitReached(max: Int)

    /// Message for the user; never includes file contents.
    func message(for name: String) -> String {
        switch self {
        case .notFileURL: "\(name) is not a file on this Mac and was skipped."
        case .directory: "\(name) is a folder. Attach files here, and add folders under Skill folders."
        case .notDirectory: "\(name) is a file. Skill folders must be folders."
        case .missing: "\(name) no longer exists and was skipped."
        case .unreadable: "\(name) cannot be read. Check its permissions."
        case .duplicate: "\(name) is already attached."
        case .tooLarge(let bytes):
            "\(name) is \(String(format: "%.1f", Double(bytes) / 1_048_576)) MB, which is too large to attach."
        case .limitReached(let max): "The limit of \(max) is reached, so \(name) was skipped."
        }
    }
}

nonisolated struct Rejected: Sendable, Equatable {
    let name: String
    let reason: DropRejection
}

nonisolated struct AttachmentInfo: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case file, directory, missing }
    let url: URL
    let kind: Kind
    let bytes: Int
    let isReadable: Bool
    /// Token estimate when the file is small enough to inline, else 0 (path only). Always 0 for secret files.
    let inlineTokens: Int
}

nonisolated protocol AttachmentInspecting: Sendable {
    func inspect(_ url: URL, policy: AttachmentPolicy) async -> AttachmentInfo
}

/// Stats the file and, for small non-secret files, reads a bounded prefix to estimate tokens. Runs off the main actor.
nonisolated struct FileAttachmentInspector: AttachmentInspecting {
    /// Complexity: O(min(size, inline cap)) time, O(inline cap) space
    @concurrent func inspect(_ url: URL, policy: AttachmentPolicy) async -> AttachmentInfo {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .isReadableKey]
        guard let values = try? url.resourceValues(forKeys: keys), FileManager.default.fileExists(atPath: url.path) else {
            return AttachmentInfo(url: url, kind: .missing, bytes: 0, isReadable: false, inlineTokens: 0)
        }
        let readable = values.isReadable ?? false
        if values.isDirectory == true {
            return AttachmentInfo(url: url, kind: .directory, bytes: 0, isReadable: readable, inlineTokens: 0)
        }
        let bytes = values.fileSize ?? 0
        let tokens = readable && !AttachmentPolicy.isSecret(url: url)
            ? Self.inlineTokens(url, bytes: bytes, cap: policy.inlineMaxTokens) : 0
        return AttachmentInfo(url: url, kind: .file, bytes: bytes, isReadable: readable, inlineTokens: tokens)
    }

    /// Rough bytes-per-token upper bound used to skip reading files that are clearly too large to inline.
    private static let bytesPerTokenBound = 8

    private static func inlineTokens(_ url: URL, bytes: Int, cap: Int) -> Int {
        guard bytes > 0, bytes <= cap * bytesPerTokenBound,
              let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes) else { return 0 }
        let tokens = TokenEstimator.estimate(data)
        return tokens <= cap ? tokens : 0
    }
}

nonisolated struct Attachment: Sendable, Equatable, Identifiable {
    let url: URL
    let bytes: Int
    let inlineTokens: Int
    let isSecret: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
}
