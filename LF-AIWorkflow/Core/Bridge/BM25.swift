//
//  BM25.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// BM25 ranking over text chunks via `lf_bm25`. The C index lives only inside one call.
nonisolated enum BM25 {
    static let defaultK1 = 1.2
    static let defaultB = 0.75

    /// Returns up to `k` best chunks, score descending, ties by lower index.
    /// Complexity: O(total bytes + n + m log k) time, O(total tokens + n + k) space
    static func topK(chunks: [String], query: String, k: Int) throws(LFCoreError)
        -> [(index: Int, score: Double)]
    {
        guard k > 0, !chunks.isEmpty, !query.isEmpty else { return [] }
        let bytes = chunks.map { Array($0.utf8) }
        let flat = bytes.flatMap { $0 }
        var offsets: [Int] = []
        var acc = 0
        for b in bytes { offsets.append(acc); acc += b.count }
        var ids = [UInt32](repeating: 0, count: k)
        var scores = [Double](repeating: 0, count: k)
        var q = query
        var failureErrno: Int32 = 0
        let count: Int = flat.withUnsafeBufferPointer { fp in
            let base = UnsafeRawPointer(fp.baseAddress)?.assumingMemoryBound(to: CChar.self)
            var spans = (0..<bytes.count).map { i in
                lf_text_span(ptr: bytes[i].isEmpty ? nil : base.map { $0 + offsets[i] }, len: bytes[i].count)
            }
            guard let index = lf_bm25_create(&spans, spans.count, defaultK1, defaultB) else {
                failureErrno = errno
                return -1
            }
            let result = q.withUTF8 { qp in
                Int(lf_bm25_query(index, UnsafeRawPointer(qp.baseAddress)?.assumingMemoryBound(to: CChar.self),
                                  qp.count, k, &ids, &scores))
            }
            if result < 0 { failureErrno = errno }  // capture before free() can clobber it
            lf_bm25_free(index)
            return result
        }
        if count < 0 { throw .posix(failureErrno) }
        return (0..<count).map { (Int(ids[$0]), scores[$0]) }
    }
}

/// Splits text into paragraph-aligned chunks of roughly `targetTokens` tokens.
nonisolated enum Chunker {
    /// A chunk never exceeds 2x target unless it is a single paragraph that is itself larger.
    /// Complexity: O(n) time, O(n) space
    static func chunks(_ text: String, targetTokens: Int = 400) -> [String] {
        let target = max(targetTokens, 1)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        var current = ""
        var currentTokens = 0
        for p in paragraphs {
            let t = TokenEstimator.estimate(p)
            if currentTokens > 0, currentTokens + t > 2 * target {
                out.append(current)
                current = ""
                currentTokens = 0
            }
            current = current.isEmpty ? p : current + "\n\n" + p
            currentTokens += t
            if currentTokens >= target {
                out.append(current)
                current = ""
                currentTokens = 0
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
