//
//  TextCleaner.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// Whitespace collapsing, cross-page boilerplate removal and duplicate detection over `lf_textclean`.
nonisolated enum TextCleaner {

    /// Complexity: O(n) time, O(n) space
    static func collapse(_ text: String) -> String {
        String(decoding: collapseBytes(Array(text.utf8)), as: UTF8.self)
    }

    /// Byte-exact variant (non-UTF-8 bytes survive).
    /// Complexity: O(n) time, O(n) space
    static func collapseBytes(_ bytes: [UInt8]) -> [UInt8] {
        var buf = bytes
        let n = buf.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Int(lf_text_collapse_ws(base.assumingMemoryBound(to: CChar.self), raw.count))
        }
        buf.removeLast(buf.count - n)
        return buf
    }

    /// Complexity: O(total bytes) expected time, O(total bytes) space
    static func removeBoilerplate(_ pages: [String], minPages: Int = 3) throws(LFCoreError)
        -> (pages: [String], removedLines: Int)
    {
        let r = try removeBoilerplateBytes(pages.map { Array($0.utf8) }, minPages: minPages)
        return (r.pages.map { String(decoding: $0, as: UTF8.self) }, r.removedLines)
    }

    /// Byte-exact variant of `removeBoilerplate`.
    /// Complexity: O(total bytes) expected time, O(total bytes) space
    static func removeBoilerplateBytes(_ pages: [[UInt8]], minPages: Int = 3) throws(LFCoreError)
        -> (pages: [[UInt8]], removedLines: Int)
    {
        let n = pages.count
        if n == 0 { return ([], 0) }
        let flat = pages.flatMap { $0 }
        var offsets: [Int] = []
        var acc = 0
        for p in pages { offsets.append(acc); acc += p.count }
        var outBuf = [CChar](repeating: 0, count: max(acc, 1))
        var lens = [Int](repeating: 0, count: n)
        let caps = pages.map { $0.count }
        let removed: Int = flat.withUnsafeBufferPointer { fp in
            outBuf.withUnsafeMutableBufferPointer { op in
                let fbase = UnsafeRawPointer(fp.baseAddress)?.assumingMemoryBound(to: CChar.self)
                var spans = (0..<n).map { i in
                    lf_text_span(ptr: pages[i].isEmpty ? nil : fbase.map { $0 + offsets[i] }, len: pages[i].count)
                }
                var outs: [UnsafeMutablePointer<CChar>?] = (0..<n).map { i in op.baseAddress.map { b in b + offsets[i] } }
                return lens.withUnsafeMutableBufferPointer { lp in
                    Int(lf_textclean_boilerplate(&spans, n, max(minPages, 0), &outs, caps, lp.baseAddress))
                }
            }
        }
        if removed < 0 { throw .posix(errno) }
        let result = (0..<n).map { i in
            outBuf[offsets[i]..<(offsets[i] + lens[i])].map { UInt8(bitPattern: $0) }
        }
        return (result, removed)
    }

    /// `result[i]` is the index of the first identical earlier page, or nil.
    /// Complexity: O(total bytes) expected time, O(total bytes) space
    static func duplicates(_ pages: [String]) -> [Int?] {
        let n = pages.count
        if n == 0 { return [] }
        let bytes = pages.map { Array($0.utf8) }
        let flat = bytes.flatMap { $0 }
        var offsets: [Int] = []
        var acc = 0
        for p in bytes { offsets.append(acc); acc += p.count }
        var dup = [Int](repeating: -1, count: n)
        let rc: Int32 = flat.withUnsafeBufferPointer { fp in
            let fbase = UnsafeRawPointer(fp.baseAddress)?.assumingMemoryBound(to: CChar.self)
            var spans = (0..<n).map { i in
                lf_text_span(ptr: bytes[i].isEmpty ? nil : fbase.map { $0 + offsets[i] }, len: bytes[i].count)
            }
            return dup.withUnsafeMutableBufferPointer { dp in
                lf_textclean_dedupe(&spans, n, dp.baseAddress)
            }
        }
        guard rc == 0 else { return Array(repeating: nil, count: n) }
        return dup.map { $0 >= 0 ? $0 : nil }
    }
}
