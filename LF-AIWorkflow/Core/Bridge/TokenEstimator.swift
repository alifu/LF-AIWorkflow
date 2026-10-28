//
//  TokenEstimator.swift
//  LF-AIWorkflow
//

import Foundation
import LFCore

/// Fast heuristic Claude token estimate (typically within about 15%).
nonisolated enum TokenEstimator {
    /// Complexity: O(n) time, O(1) space (O(n) if the string is not contiguous UTF-8)
    static func estimate(_ s: String) -> Int {
        var copy = s
        return copy.withUTF8 { Int(lf_tokens_estimate($0.baseAddress, $0.count)) }
    }

    /// Complexity: O(n) time, O(1) space
    static func estimate(_ d: Data) -> Int {
        d.withUnsafeBytes { Int(lf_tokens_estimate($0.baseAddress, $0.count)) }
    }
}
