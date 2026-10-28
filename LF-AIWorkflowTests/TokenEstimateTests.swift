//
//  TokenEstimateTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

struct TokenEstimateTests {

    private struct Reference: Decodable {
        struct Entry: Decodable { let count: Int }
        let files: [String: Entry]
    }

    private static let names = ["tok_english.txt", "tok_swift.txt", "tok_json.txt", "tok_mixed.txt"]

    @Test(arguments: names)
    func estimateWithin15PercentOfClaudeCount(name: String) throws {
        let ref = try JSONDecoder().decode(Reference.self, from: loadFixture("tokens_reference.json"))
        let expected = try #require(ref.files[name]).count
        let est = TokenEstimator.estimate(try loadFixture(name))
        #expect(abs(Double(est - expected)) <= 0.15 * Double(expected), "est \(est) vs ref \(expected)")
    }

    @Test func emptyAndNullAreZero() {
        #expect(lf_tokens_estimate(nil, 0) == 0)
        #expect(TokenEstimator.estimate("") == 0)
        #expect(TokenEstimator.estimate(Data()) == 0)
    }

    @Test func singleCharIsOne() {
        #expect(TokenEstimator.estimate("a") == 1)
        #expect(TokenEstimator.estimate("{") == 1)
        #expect(TokenEstimator.estimate("7") == 1)
    }

    @Test func whitespaceOnlyIsSmall() {
        #expect(TokenEstimator.estimate("     ") <= 1)
        #expect(TokenEstimator.estimate("\n\n\n") <= 3)
        #expect(TokenEstimator.estimate(" \n \n") <= 2)
    }

    @Test func multibyteCosts() {
        #expect(TokenEstimator.estimate("日本語") == 3)
        #expect(TokenEstimator.estimate("é") == 1)
        #expect(TokenEstimator.estimate("🚀") == 2)
    }

    @Test func invalidUTF8DoesNotCrash() {
        #expect(TokenEstimator.estimate(Data([0xFF])) >= 1)
        #expect(TokenEstimator.estimate(Data([0xE3, 0x81])) >= 1)
        #expect(TokenEstimator.estimate(Data([0x80, 0x80, 0xC0, 0xC1, 0xF5])) >= 5)
    }

    @Test func truncatedMultibyteAtBufferEnd() {
        for seq in [[0xE3], [0xE3, 0x81], [0xF0, 0x9F], [0xF0, 0x9F, 0x9A], [0xC3]] as [[UInt8]] {
            let est = TokenEstimator.estimate(Data(Array("ab ".utf8) + seq))
            #expect(est >= 1 + seq.count)
        }
        // Lead byte followed by a non-continuation byte.
        #expect(TokenEstimator.estimate(Data([0xE3, 0x41])) >= 2)
    }

    @Test func monotonicUnderConcatenation() throws {
        let samples = ["hello world", "  indent", "12345", "{\"a\":1}", "日本", "\n\n", "x", "🚀🎉", "foo_bar(baz)"]
        for a in samples {
            for b in samples {
                let joined = TokenEstimator.estimate(a + b)
                #expect(joined <= TokenEstimator.estimate(a) + TokenEstimator.estimate(b) + 1, "\(a)|\(b)")
            }
        }
    }

    // Wall-clock guard (TD-011). ASan slows code several times over, so it is skipped there.
    @Test(.enabled(if: lf_core_built_with_sanitizer() == 0, "wall-clock guard is meaningless under ASan/UBSan"))
    func tenMegabytesRunsFast() {
        let chunk = Array("The quick brown fox, 12345 jumps over {\"lazy\": 日本} dogs.\n".utf8)
        var big = Data(capacity: 10_000_000 + chunk.count)
        while big.count < 10_000_000 { big.append(contentsOf: chunk) }
        // Best of three filters out CPU spikes from the hosted app and parallel tests. The bound is looser for
        // unoptimised Debug builds; an O(n^2) regression would still miss it by orders of magnitude.
        #if DEBUG
        let limit = Duration.milliseconds(500)
        #else
        let limit = Duration.milliseconds(50)
        #endif
        var est = 0
        var best = Duration.seconds(60)
        for _ in 0..<3 {
            let start = ContinuousClock.now
            est = TokenEstimator.estimate(big)
            best = min(best, ContinuousClock.now - start)
        }
        #expect(est > 0)
        #expect(best < limit, "best of 3 took \(best), limit \(limit)")
    }
}
