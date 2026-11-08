//
//  HostPolicyTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct HostPolicyTests {
    private let policy = HostPolicy.standard

    @Test(arguments: [
        "https://example.com/", "http://example.com/path?q=1", "https://sub.example.co.uk:443/",
        "http://example.com:80/", "http://8.8.8.8/", "http://[2606:4700:4700::1111]/",
        "http://172.32.0.1/", "http://100.63.0.1/", "http://example.com./",
    ])
    func allows(_ s: String) throws {
        let url = try #require(URL(string: s))
        #expect(policy.check(url).isAllowed, "\(s)")
    }

    @Test(arguments: [
        "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x", "ftp://example.com/",
        "http://localhost/", "http://foo.localhost/", "http://printer.local/", "http://db.internal/",
        "http://intranet/", "http://example.com@127.0.0.1/", "http://user:pw@example.com/",
        "http://127.0.0.1/", "http://127.1/", "http://2130706433/", "http://0x7f.1/", "http://0x7f000001/",
        "http://0177.0.0.1/", "http://0.0.0.0/", "http://10.0.0.1/", "http://100.64.0.1/",
        "http://169.254.169.254/", "http://172.16.0.1/", "http://172.31.255.255/", "http://192.0.0.1/",
        "http://192.168.1.1/", "http://198.18.0.1/", "http://198.19.255.255/", "http://224.0.0.1/",
        "http://240.0.0.1/", "http://255.255.255.255/", "http://3232235777/", "http://1.2.3.4.5/",
        "http://[::1]/", "http://[::]/", "http://[fc00::1]/", "http://[fd12::1]/", "http://[fe80::1]/",
        "http://[ff02::1]/", "http://[::ffff:127.0.0.1]/", "http://[::ffff:7f00:1]/",
        "http://[::ffff:10.0.0.1]/", "http://[::127.0.0.1]/", "http://[64:ff9b::7f00:1]/",
        "http://[2002:7f00:1::]/",
        "http://192.0.2.1/", "http://198.51.100.7/", "http://203.0.113.9/",
        "http://[2001::1]/", "http://[2001:0:4136:e378::1]/", "http://[2001:db8::1]/",
        "http://[64:ff9b:1::1]/", "http://[64:ff9b:1:2::3]/",
        "https://example.com:8080/", "http://example.com:22/",
    ])
    func blocks(_ s: String) throws {
        let url = try #require(URL(string: s))
        #expect(!policy.check(url).isAllowed, "\(s)")
    }

    @Test func loopbackOnlyWhenTestingAllows() throws {
        let t = HostPolicy.testing(allowLoopback: true)
        #expect(t.check(try #require(URL(string: "http://127.0.0.1/"))).isAllowed)
        #expect(t.check(try #require(URL(string: "http://[::1]/"))).isAllowed)
        #expect(!t.check(try #require(URL(string: "http://10.0.0.1/"))).isAllowed)
    }

    @Test func anyBlockedAddressBlocksHost() {
        let ok = IPAddress.v4(0x0808_0808)
        let bad = IPAddress.v4(0x7F00_0001)
        #expect(policy.check(addresses: [ok]).isAllowed)
        #expect(!policy.check(addresses: [ok, bad]).isAllowed)
        #expect(!policy.check(addresses: []).isAllowed)
    }

    @Test func inetAtonParsing() {
        #expect(HostPolicy.parseIPv4("127.1") == 0x7F00_0001)
        #expect(HostPolicy.parseIPv4("0x7f.1") == 0x7F00_0001)
        #expect(HostPolicy.parseIPv4("0177.0.0.1") == 0x7F00_0001)
        #expect(HostPolicy.parseIPv4("2130706433") == 0x7F00_0001)
        #expect(HostPolicy.parseIPv4("256.1.1.1") == nil)
        #expect(HostPolicy.parseIPv4("example.com") == nil)
        #expect(HostPolicy.parseIPv4("09.1") == nil)
    }

    @Test func fakeResolverFeedsPolicy() async throws {
        struct Fake: HostResolving {
            func addresses(for host: String) async throws -> [IPAddress] { [.v4(0x0A00_0001)] }
        }
        let addrs = try await Fake().addresses(for: "evil.example.com")
        #expect(!policy.check(addresses: addrs).isAllowed)
    }
}
