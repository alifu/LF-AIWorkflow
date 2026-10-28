//
//  RingBuffer.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// Swift owner of one `lf_ringbuf` handle. Not thread-safe: use from a single owner.
nonisolated final class RingBuffer {
    private let handle: OpaquePointer

    /// Creates a buffer holding at most `capacity` bytes.
    init(capacity: Int) throws {
        guard capacity > 0, let h = lf_ringbuf_create(size_t(capacity)) else {
            throw LFCoreError.posix(capacity > 0 ? errno : EINVAL)
        }
        handle = h
    }

    deinit { lf_ringbuf_destroy(handle) }

    /// Bytes currently stored.
    var count: Int { Int(lf_ringbuf_size(handle)) }

    /// Total capacity in bytes.
    var capacity: Int { Int(lf_ringbuf_capacity(handle)) }

    /// Total bytes overwritten or discarded.
    var dropped: UInt64 { lf_ringbuf_dropped(handle) }

    /// Appends bytes, overwriting the oldest when full.
    /// Complexity: O(k) time, O(1) space
    @discardableResult
    func write(_ data: Data) -> Int {
        data.withUnsafeBytes { Int(lf_ringbuf_write(handle, $0.baseAddress, $0.count)) }
    }

    /// Consumes up to `max` bytes, oldest first.
    /// Complexity: O(m) time, O(m) space
    func read(max: Int) -> Data {
        let cap = Swift.min(Swift.max(max, 0), count)
        return Data([UInt8](unsafeUninitializedCapacity: cap) { buf, n in
            n = Int(lf_ringbuf_read(handle, buf.baseAddress, cap))
        })
    }

    /// Copies all stored bytes without consuming them.
    /// Complexity: O(C) time, O(C) space
    func snapshot() -> Data {
        let cap = count
        return Data([UInt8](unsafeUninitializedCapacity: cap) { buf, n in
            n = Int(lf_ringbuf_snapshot(handle, buf.baseAddress, cap))
        })
    }
}
