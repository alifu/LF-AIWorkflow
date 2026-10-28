//
//  CStringArray.swift
//  LF-AIWorkflow
//

import Foundation

/// Owns `strdup`ed copies of strings plus a NULL-terminated pointer array, for argv/envp.
/// Frees everything in `deinit`. Keep the instance alive while C uses `pointer`.
nonisolated final class CStringArray {
    private let storage: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    let count: Int

    /// Complexity: O(total bytes) time, O(total bytes) space
    init(_ strings: [String]) {
        count = strings.count
        storage = .allocate(capacity: strings.count + 1)
        for (i, s) in strings.enumerated() { storage[i] = strdup(s) }
        storage[strings.count] = nil
    }

    deinit {
        for i in 0..<count { free(storage[i]) }
        storage.deallocate()
    }

    /// NULL-terminated array, usable as `const char *const *`.
    var pointer: UnsafePointer<UnsafePointer<CChar>?> {
        UnsafeRawPointer(storage).assumingMemoryBound(to: UnsafePointer<CChar>?.self)
    }
}
