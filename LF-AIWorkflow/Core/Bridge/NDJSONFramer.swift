//
//  NDJSONFramer.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// Swift owner of one `lf_ndjson` handle. Not thread-safe: use from a single owner.
nonisolated final class NDJSONFramer {
    private let handle: OpaquePointer

    /// Collects borrowed lines as copied `Data`.
    private final class Box {
        var lines: [Data] = []
    }

    private static let collect: lf_ndjson_line_cb = { line, len, ctx in
        guard let ctx, let line else { return 0 }
        let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
        box.lines.append(Data(bytes: line, count: len))
        return 0
    }

    /// `maxLine` 0 selects the C default (16 MiB).
    init(maxLine: Int = 0) throws {
        guard let h = lf_ndjson_create(size_t(maxLine)) else { throw LFCoreError.posix(errno) }
        handle = h
    }

    deinit { lf_ndjson_destroy(handle) }

    /// Lines dropped for exceeding the maximum line length.
    var oversizeCount: UInt64 { lf_ndjson_oversize_count(handle) }

    /// Feeds a chunk and returns the complete lines it finished. Throws `LFCoreError.posix` on allocation failure.
    /// Complexity: O(k) time, O(k) space
    func feed(_ data: Data) throws -> [Data] {
        let box = Box()
        let (rc, err): (Int32, Int32) = withExtendedLifetime(box) {
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            return data.withUnsafeBytes {
                let rc = Int32(truncatingIfNeeded: lf_ndjson_feed(handle, $0.baseAddress, $0.count, Self.collect, ctx))
                return (rc, errno)
            }
        }
        if rc < 0 { throw LFCoreError.posix(err) }
        return box.lines
    }

    /// Flushes a final unterminated line. Throws `LFCoreError.posix` on allocation failure.
    func finish() throws -> [Data] {
        let box = Box()
        let (rc, err): (Int32, Int32) = withExtendedLifetime(box) {
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            let rc = Int32(truncatingIfNeeded: lf_ndjson_finish(handle, Self.collect, ctx))
            return (rc, errno)
        }
        if rc < 0 { throw LFCoreError.posix(err) }
        return box.lines
    }

    /// Raw (escape-preserving) string value at a dotted key path, or nil.
    /// Complexity: O(line) time, O(1) space
    static func field(_ path: String, in line: Data) -> String? {
        line.withUnsafeBytes { raw -> String? in
            let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
            var out: UnsafePointer<CChar>?
            var outLen = 0
            guard lf_ndjson_get_string(base, raw.count, path, &out, &outLen) == 0, let out else { return nil }
            return String(decoding: UnsafeRawBufferPointer(start: out, count: outLen), as: UTF8.self)
        }
    }

    /// Integer value at a dotted key path, or nil.
    /// Complexity: O(line) time, O(1) space
    static func intField(_ path: String, in line: Data) -> Int64? {
        line.withUnsafeBytes { raw -> Int64? in
            let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
            var value: Int64 = 0
            return lf_ndjson_get_int64(base, raw.count, path, &value) == 0 ? value : nil
        }
    }
}
