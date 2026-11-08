//
//  Slug.swift
//  LF-AIWorkflow
//

import Foundation

/// Turns untrusted text into a safe single path component.
nonisolated enum Slug {
    static let fallback = "page"

    /// Output is `[a-z0-9-]`, never empty, never contains `..`, at most `maxLength` characters.
    /// Complexity: O(n) time, O(n) space
    static func make(_ untrusted: String, maxLength: Int = 40) -> String {
        var out = ""
        var lastDash = true
        for scalar in untrusted.unicodeScalars {
            let v = scalar.value
            let isAlnum = (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39)
            let isUpper = v >= 0x41 && v <= 0x5A
            if isAlnum || isUpper {
                out.unicodeScalars.append(isUpper ? Unicode.Scalar(v + 32)! : scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let limited = String(out.prefix(max(1, maxLength)))
        let trimmed = limited.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Double-quoted YAML scalar with `\`, `"` and control characters escaped (one line, no injection).
    /// Complexity: O(n) time, O(n) space
    static func yamlQuoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || scalar.value == 0x2028 || scalar.value == 0x2029 || scalar.value == 0x85 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
