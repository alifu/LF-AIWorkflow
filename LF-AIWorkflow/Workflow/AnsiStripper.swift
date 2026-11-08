//
//  AnsiStripper.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum AnsiStripper {
    private static let esc: Unicode.Scalar = "\u{1B}"
    private static let bel: Unicode.Scalar = "\u{07}"

    /// Removes ANSI escape sequences (CSI, OSC, two-byte escapes). A truncated trailing sequence is dropped.
    /// Complexity: O(n) time, O(n) space
    static func strip(_ text: String) -> String {
        guard text.unicodeScalars.contains(esc) else { return text }
        var out = String.UnicodeScalarView()
        var rest = text.unicodeScalars[...]
        while let scalar = rest.popFirst() {
            guard scalar == esc else { out.append(scalar); continue }
            guard let kind = rest.popFirst() else { break }
            switch kind {
            case "[": skipCSI(&rest)
            case "]": skipOSC(&rest)
            case "(", ")", "#", "%": _ = rest.popFirst()   // charset selection: one more byte
            default: break                                  // two-byte escape such as ESC 7
            }
        }
        return String(out)
    }

    /// Parameter bytes 0x30-0x3F, intermediates 0x20-0x2F, one final byte 0x40-0x7E.
    private static func skipCSI(_ rest: inout Substring.UnicodeScalarView) {
        while let scalar = rest.popFirst() {
            if (0x40...0x7E).contains(scalar.value) { return }
        }
    }

    /// Ends at BEL or ST (ESC backslash).
    private static func skipOSC(_ rest: inout Substring.UnicodeScalarView) {
        while let scalar = rest.popFirst() {
            if scalar == bel { return }
            if scalar == esc { _ = rest.popFirst(); return }
        }
    }
}
