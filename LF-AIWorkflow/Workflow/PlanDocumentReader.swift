//
//  PlanDocumentReader.swift
//  LF-AIWorkflow
//

import Foundation

/// Builds `ContextDocument`s for the Plan prompt: small files are read and hashed (so they can be inlined and
/// deduped through `sentHashes`); larger ones stay path-only.
nonisolated enum PlanDocumentReader {
    /// Rough bytes-per-token upper bound used to skip reading files that are clearly too large to inline.
    private static let bytesPerTokenBound = 8
    private static let fnvOffset: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x100_0000_01b3

    /// FNV-1a 64, the same hash `FolderScanner` reports for file contents.
    /// Complexity: O(n) time, O(1) space
    static func hash(_ data: Data) -> UInt64 {
        data.reduce(fnvOffset) { ($0 ^ UInt64($1)) &* fnvPrime }
    }

    /// Complexity: O(min(size, inline cap)) time, O(inline cap) space
    static func read(_ url: URL, inlineMaxTokens: Int) -> ContextDocument {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let limit = UInt64(max(0, inlineMaxTokens) * bytesPerTokenBound)
        guard size > 0, size <= limit, !AttachmentPolicy.isSecret(url: url),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return ContextDocument(url: url, byteSize: size, hash: nil, text: nil)
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Int(size)), let text = String(data: data, encoding: .utf8) else {
            return ContextDocument(url: url, byteSize: size, hash: nil, text: nil)
        }
        return ContextDocument(url: url, byteSize: size, hash: hash(data), text: text)
    }
}
