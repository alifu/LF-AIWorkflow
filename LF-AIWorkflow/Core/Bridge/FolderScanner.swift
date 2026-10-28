//
//  FolderScanner.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// A regular file found by `FolderScanner`.
nonisolated struct ScannedFile: Sendable, Hashable {
    let path: String
    let size: UInt64
    /// FNV-1a 64 of the contents; nil when skipped (too large) or unreadable.
    let hash: UInt64?
}

/// Recursive folder walk backed by `lf_scan_walk`.
nonisolated enum FolderScanner {

    struct Options: Sendable {
        /// Root's children are depth 1; negative means unlimited.
        var maxDepth: Int = -1
        /// Extensions without dot, case-insensitive; empty means every regular file.
        var extensions: [String] = []
        /// Files larger than this are reported unhashed; 0 hashes everything.
        var maxHashBytes: UInt64 = 0
        var includeHidden = false
    }

    private final class Box {
        var files: [ScannedFile] = []
    }

    private static let collect: lf_scan_cb = { entry, ctx in
        guard let entry, let ctx else { return 1 }
        let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
        let raw = UnsafeBufferPointer(start: UnsafeRawPointer(entry.pointee.path)
            .assumingMemoryBound(to: UInt8.self), count: entry.pointee.path_len)
        let path = String(decoding: raw, as: UTF8.self)
        box.files.append(ScannedFile(
            path: path,
            size: entry.pointee.size,
            hash: entry.pointee.hashed != 0 ? entry.pointee.hash : nil))
        return 0
    }

    /// Scans `root` and returns every matching regular file in walk order.
    /// Complexity: O(F + total bytes) time, O(F) space
    static func scan(_ root: URL, options: Options = Options()) throws -> [ScannedFile] {
        let box = Box()
        let exts = options.extensions.isEmpty ? nil : CStringArray(options.extensions)
        let count: Int = try root.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw LFCoreError.posix(EINVAL) }
            return try withExtendedLifetime((box, exts)) {
                var o = lf_scan_options(
                    max_depth: Int32(clamping: options.maxDepth),
                    extensions: exts?.pointer,
                    extension_count: options.extensions.count,
                    max_hash_bytes: options.maxHashBytes,
                    include_hidden: options.includeHidden ? 1 : 0)
                let ctx = Unmanaged.passUnretained(box).toOpaque()
                let n = lf_scan_walk(path, &o, Self.collect, ctx)
                if n < 0 { throw LFCoreError.posix(errno) }
                return n
            }
        }
        precondition(count == box.files.count)
        return box.files
    }
}
