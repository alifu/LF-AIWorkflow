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

    /// Returns nil when any `strdup` fails (ENOMEM); nothing is leaked and argv is never silently truncated.
    /// Complexity: O(total bytes) time, O(total bytes) space
    init?(_ strings: [String]) {
        count = strings.count
        storage = .allocate(capacity: strings.count + 1)
        storage.initialize(repeating: nil, count: strings.count + 1)
        for (i, s) in strings.enumerated() {
            guard let copy = strdup(s) else {
                for j in 0..<i { free(storage[j]) }
                storage.deallocate()
                return nil
            }
            storage[i] = copy
        }
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
