//
//  RingBufferTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

struct RingBufferTests {

    private func bytes(_ range: Range<Int>) -> Data { Data(range.map { UInt8($0 & 0xFF) }) }

    @Test func createZeroFailsWithEINVAL() {
        errno = 0
        #expect(lf_ringbuf_create(0) == nil)
        #expect(errno == EINVAL)
        #expect(throws: LFCoreError.posix(EINVAL)) { try RingBuffer(capacity: 0) }
    }

    @Test func destroyNullIsSafe() {
        lf_ringbuf_destroy(nil)
    }

    @Test func nullAccessorsReturnZero() {
        #expect(lf_ringbuf_size(nil) == 0)
        #expect(lf_ringbuf_capacity(nil) == 0)
        #expect(lf_ringbuf_dropped(nil) == 0)
        #expect(lf_ringbuf_write(nil, nil, 0) == 0)
        #expect(lf_ringbuf_read(nil, nil, 0) == 0)
    }

    @Test func emptyWriteReadSnapshotAreNoOps() throws {
        let rb = try RingBuffer(capacity: 8)
        #expect(rb.write(Data()) == 0)
        #expect(rb.count == 0)
        #expect(rb.read(max: 4).isEmpty)
        #expect(rb.snapshot().isEmpty)
    }

    @Test(arguments: [1, 7, 4096])
    func exactFillThenSnapshot(capacity: Int) throws {
        let rb = try RingBuffer(capacity: capacity)
        let data = bytes(0..<capacity)
        #expect(rb.write(data) == capacity)
        #expect(rb.count == capacity)
        #expect(rb.capacity == capacity)
        #expect(rb.dropped == 0)
        #expect(rb.snapshot() == data)
    }

    @Test(arguments: [1, 7, 4096])
    func overwriteKeepsLastCapacityBytes(capacity: Int) throws {
        let rb = try RingBuffer(capacity: capacity)
        let data = bytes(0..<(2 * capacity))
        rb.write(data.prefix(capacity))
        rb.write(data.suffix(capacity))
        #expect(rb.snapshot() == data.suffix(capacity))
        #expect(rb.dropped == UInt64(capacity))
    }

    @Test func wrapAroundPreservesOrder() throws {
        let rb = try RingBuffer(capacity: 10)
        rb.write(bytes(0..<8))
        #expect(rb.read(max: 4) == bytes(0..<4))
        rb.write(bytes(8..<14))
        #expect(rb.snapshot() == bytes(4..<14))
        #expect(rb.dropped == 0)
    }

    @Test func singleWriteLargerThanCapacityKeepsTail() throws {
        let rb = try RingBuffer(capacity: 5)
        #expect(rb.write(bytes(0..<12)) == 5)
        #expect(rb.snapshot() == bytes(7..<12))
        #expect(rb.dropped == 7)
    }

    @Test func readConsumesSnapshotDoesNot() throws {
        let rb = try RingBuffer(capacity: 8)
        rb.write(bytes(0..<6))
        #expect(rb.snapshot().count == 6)
        #expect(rb.snapshot().count == 6)
        #expect(rb.read(max: 100) == bytes(0..<6))
        #expect(rb.count == 0)
        #expect(rb.read(max: 4).isEmpty)
    }

    @Test func readWithSmallCapReturnsPrefix() throws {
        let rb = try RingBuffer(capacity: 8)
        rb.write(bytes(0..<6))
        #expect(rb.read(max: 2) == bytes(0..<2))
        #expect(rb.count == 4)
        #expect(rb.read(max: -3).isEmpty)
    }

    @Test func arbitraryBytesRoundTrip() throws {
        let rb = try RingBuffer(capacity: 16)
        let data = Data([0x00, 0xFF, 0xFE, 0x41, 0x00, 0xC3])
        rb.write(data)
        #expect(rb.snapshot() == data)
        #expect(rb.read(max: 16) == data)
    }
}
