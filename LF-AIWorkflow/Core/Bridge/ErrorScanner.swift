//
//  ErrorScanner.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// Extracts error lines (with context and a tail) from build/test logs via `lf_errscan_extract`.
nonisolated enum ErrorScanner {

    struct Options: Sendable {
        var contextBefore = 2
        var contextAfter = 2
        var tailLines = 20
        /// Output budget in bytes (callers pass `errorMaxTokens * 4`).
        var maxOutputBytes: Int

        init(maxOutputBytes: Int) { self.maxOutputBytes = maxOutputBytes }
    }

    /// Returns the extracted text (empty when nothing matched) and whether the budget cut it.
    /// Complexity: O(n) time, O(c + out) space
    static func extract(_ log: Data, options: Options) -> (text: String, truncated: Bool) {
        guard options.maxOutputBytes > 0 else { return ("", false) }
        var out = [CChar](repeating: 0, count: options.maxOutputBytes)
        var cut: Int32 = 0
        var o = lf_errscan_options(
            context_before: size_t(max(options.contextBefore, 0)),
            context_after: size_t(max(options.contextAfter, 0)),
            tail_lines: size_t(max(options.tailLines, 0)),
            max_output_bytes: size_t(options.maxOutputBytes))
        let written = log.withUnsafeBytes { raw in
            lf_errscan_extract(raw.baseAddress, raw.count, &o, &out, out.count, &cut)
        }
        guard written > 0 else { return ("", false) }
        let bytes = out.prefix(written).map { UInt8(bitPattern: $0) }
        return (String(decoding: bytes, as: UTF8.self), cut != 0)
    }
}
