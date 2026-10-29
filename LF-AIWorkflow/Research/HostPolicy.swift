//
//  HostPolicy.swift
//  LF-AIWorkflow
//

import Foundation
import Darwin

nonisolated enum HostVerdict: Sendable, Equatable {
    case allowed
    case blocked(String)

    var isAllowed: Bool { self == .allowed }
}

/// SSRF guard: decides whether a URL or resolved address may be fetched.
nonisolated struct HostPolicy: Sendable {
    let allowLoopback: Bool

    static let standard = HostPolicy(allowLoopback: false)
    static func testing(allowLoopback: Bool) -> HostPolicy { HostPolicy(allowLoopback: allowLoopback) }

    private static let allowedPorts: Set<Int> = [80, 443]
    private static let blockedSuffixes = [".localhost", ".local", ".internal"]

    /// Complexity: O(h) time, O(h) space for host length h.
    func check(_ url: URL) -> HostVerdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .blocked("scheme")
        }
        guard url.user == nil, url.password == nil else { return .blocked("userinfo") }
        if !allowLoopback, let port = url.port, !Self.allowedPorts.contains(port) { return .blocked("port") }
        guard var host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty else {
            return .blocked("host")
        }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains("%"), !host.contains(where: \.isWhitespace) else {
            return .blocked("host")
        }
        if host.contains(":") {
            guard let bytes = Self.parseIPv6(host) else { return .blocked("ipv6") }
            return check(addresses: [.v6(bytes)])
        }
        if let v4 = Self.parseIPv4(host) { return check(addresses: [.v4(v4)]) }
        if Self.looksNumeric(host) { return .blocked("malformed-ip") }
        if allowLoopback && host == "localhost" { return .allowed }
        if host == "localhost" || Self.blockedSuffixes.contains(where: host.hasSuffix) {
            return .blocked("reserved-name")
        }
        guard host.contains(".") else { return .blocked("single-label") }
        return .allowed
    }

    /// Blocked if ANY address is blocked. Empty list is blocked.
    /// Complexity: O(a) time, O(1) space.
    func check(addresses: [IPAddress]) -> HostVerdict {
        guard !addresses.isEmpty else { return .blocked("no-address") }
        for a in addresses where isBlocked(a) { return .blocked("address") }
        return .allowed
    }

    private func isBlocked(_ a: IPAddress) -> Bool {
        switch a {
        case .v4(let v): return isBlockedV4(v)
        case .v6(let b): return isBlockedV6(b)
        }
    }

    private func isBlockedV4(_ v: UInt32) -> Bool {
        if allowLoopback && (v >> 24) == 127 { return false }
        let ranges: [(UInt32, Int)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x6440_0000, 10), (0x7F00_0000, 8),
            (0xA9FE_0000, 16), (0xAC10_0000, 12), (0xC000_0000, 24), (0xC0A8_0000, 16),
            (0xC612_0000, 15), (0xE000_0000, 4), (0xF000_0000, 4),
            (0xC000_0200, 24), (0xC633_6400, 24), (0xCB00_7100, 24),  // RFC 5737 documentation ranges
        ]
        return ranges.contains { base, bits in (v >> UInt32(32 - bits)) == (base >> UInt32(32 - bits)) }
    }

    private func isBlockedV6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return true }
        func v4(_ i: Int) -> UInt32 {
            (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
        }
        let zeros12 = b[0..<12].allSatisfy { $0 == 0 }
        if zeros12 {
            if v4(12) == 1 { return !allowLoopback }   // ::1
            return v4(12) == 0 || isBlockedV4(v4(12))  // ::, IPv4-compatible
        }
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isBlockedV4(v4(12)) }
        // NAT64 64:ff9b::/96
        if b[0] == 0x00, b[1] == 0x64, b[2] == 0xFF, b[3] == 0x9B, b[4..<12].allSatisfy({ $0 == 0 }) {
            return isBlockedV4(v4(12))
        }
        if b[0] == 0x20 && b[1] == 0x02 { return isBlockedV4(v4(2)) }  // 6to4
        if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x00 { return true }  // Teredo 2001::/32
        if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0D && b[3] == 0xB8 { return true }  // 2001:db8::/32 documentation
        // NAT64 local-use 64:ff9b:1::/48
        if b[0] == 0x00, b[1] == 0x64, b[2] == 0xFF, b[3] == 0x9B, b[4] == 0x00, b[5] == 0x01 { return true }
        if (b[0] & 0xFE) == 0xFC { return true }                       // fc00::/7
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }       // fe80::/10
        if b[0] == 0xFF { return true }                                // ff00::/8
        return false
    }

    // MARK: parsing

    private static func looksNumeric(_ host: String) -> Bool {
        guard let last = host.split(separator: ".", omittingEmptySubsequences: false).last else { return false }
        return last.first?.isASCII == true && (last.first!.isNumber) || last.hasPrefix("0x")
    }

    /// inet_aton semantics: 1-4 parts; decimal, 0x hex, 0 octal; last part fills the rest.
    /// Complexity: O(h) time, O(1) space.
    static func parseIPv4(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var nums: [UInt64] = []
        for p in parts {
            guard let n = parseComponent(p) else { return nil }
            nums.append(n)
        }
        let last = nums.removeLast()
        var result: UInt64 = 0
        for n in nums {
            guard n <= 255 else { return nil }
            result = (result << 8) | n
        }
        let remainingBits = 8 * (4 - nums.count)
        guard last < (UInt64(1) << UInt64(remainingBits)) else { return nil }
        result = (result << UInt64(remainingBits)) | last
        return UInt32(result)
    }

    private static func parseComponent(_ p: Substring) -> UInt64? {
        guard !p.isEmpty, p.allSatisfy({ $0.isASCII }) else { return nil }
        var radix = 10
        var digits = Substring(p)
        if p.hasPrefix("0x") || p.hasPrefix("0X") {
            radix = 16
            digits = p.dropFirst(2)
            if digits.isEmpty { return 0 }
        } else if p.count > 1 && p.hasPrefix("0") {
            radix = 8
            digits = p.dropFirst()
        }
        guard digits.count <= 16 else { return nil }
        return UInt64(digits, radix: radix)
    }

    private static func parseIPv6(_ s: String) -> [UInt8]? {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, s, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }
}
