//
//  URLNormalizerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct URLNormalizerTests {
    @Test(arguments: [
        ("HTTP://Example.COM:80/a#frag", "http://example.com/a"),
        ("https://example.com:443", "https://example.com/"),
        ("https://example.com/p?b=2&a=1", "https://example.com/p?a=1&b=2"),
        ("https://example.com/p?utm_source=x&gclid=1&fbclid=2&mc_eid=3&q=ok", "https://example.com/p?q=ok"),
        ("https://example.com/p?utm_source=x", "https://example.com/p"),
        ("https://example.com:8443/x", "https://example.com:8443/x"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(URLNormalizer.normalize(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "ftp://example.com/", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hi",
        "https://user:pw@example.com/", "http://example.com@127.0.0.1/", "", "   ", "not a url",
        "https:///nohost",
    ])
    func rejects(input: String) {
        #expect(URLNormalizer.normalize(input) == nil)
    }

    @Test func rejectsOverlong() {
        #expect(URLNormalizer.normalize("https://example.com/" + String(repeating: "a", count: 2100)) == nil)
    }

    @Test func idempotent() throws {
        let once = try #require(URLNormalizer.normalize("HTTPS://Example.com:443/a?z=1&utm_x=2&b=3#f"))
        let twice = URLNormalizer.normalize(once.absoluteString)
        #expect(twice == once)
    }

    @Test func sameSiteStripsWww() throws {
        let a = try #require(URL(string: "https://www.example.com/a"))
        let b = try #require(URL(string: "https://example.com/b"))
        let c = try #require(URL(string: "https://docs.example.com/"))
        #expect(URLNormalizer.sameSite(a, b))
        #expect(!URLNormalizer.sameSite(a, c))
    }
}
