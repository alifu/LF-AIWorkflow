//
//  BM25Tests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

struct BM25Tests {

    private let corpus = [
        "The quick brown fox jumps over the lazy dog",
        "Swift concurrency uses actors and structured tasks for safe data isolation",
        "Actors isolate mutable state; actors serialize access to actors",
        "Cooking pasta requires boiling water and salt",
    ]

    @Test func onTopicChunkRanksFirst() throws {
        let r = try BM25.topK(chunks: corpus, query: "swift actors concurrency", k: 3)
        #expect(r.first?.index == 1)
        #expect(r.count == 2)
        #expect(r[0].score >= r[1].score)
    }

    @Test func kLargerThanMatchesReturnsMatchesOnly() throws {
        let r = try BM25.topK(chunks: corpus, query: "the", k: 50)
        #expect(r.count == 1)
        #expect(r[0].index == 0)
    }

    @Test func kZeroReturnsEmpty() throws {
        #expect(try BM25.topK(chunks: corpus, query: "actors", k: 0).isEmpty)
    }

    @Test func emptyQueryOrCorpusReturnsEmpty() throws {
        #expect(try BM25.topK(chunks: corpus, query: "", k: 3).isEmpty)
        #expect(try BM25.topK(chunks: [], query: "actors", k: 3).isEmpty)
        #expect(try BM25.topK(chunks: ["", ""], query: "actors", k: 3).isEmpty)
    }

    @Test func unknownTermsReturnEmpty() throws {
        #expect(try BM25.topK(chunks: corpus, query: "zyzzyva qqqq", k: 3).isEmpty)
    }

    @Test func singleCharacterTokensIgnored() throws {
        #expect(try BM25.topK(chunks: ["a b c"], query: "a b", k: 3).isEmpty)
    }

    @Test func tiesBreakByLowerIdAndAreDeterministic() throws {
        let same = Array(repeating: "identical chunk text", count: 5)
        let r = try BM25.topK(chunks: same, query: "identical", k: 3)
        #expect(r.map(\.index) == [0, 1, 2])
        #expect(try BM25.topK(chunks: same, query: "identical", k: 3).map(\.index) == [0, 1, 2])
    }

    @Test func caseInsensitiveAndNonAsciiWords() throws {
        let r = try BM25.topK(chunks: ["Café au lait", "tea"], query: "CAFé", k: 2)
        #expect(r.map(\.index) == [0])
    }

    @Test func foldsGreekCyrillicArmenianGeorgianAndExtended() throws {
        let pairs = [("ΑΒΓ", "αβγ"), ("ПРИВЕТ", "привет"), ("ԱԲԳ", "աբգ"),
                     ("ႠႡႢ", "ⴀⴁⴂ"), ("ḀḂḄ", "ḁḃḅ"), ("ѠѢѤ", "ѡѣѥ"), ("ἈἉἊ", "ἀἁἂ")]
        let unassigned = try BM25.topK(chunks: ["a\u{3A2}b tail", "other"], query: "a\u{3C2}b", k: 2)
        #expect(!unassigned.map(\.index).contains(0), "U+03A2 is unassigned and must not fold")
        for (upper, lower) in pairs {
            let r = try BM25.topK(chunks: [lower + " tail", "other words"], query: upper, k: 2)
            #expect(r.map(\.index) == [0], "\(upper) should match \(lower)")
            let r2 = try BM25.topK(chunks: [upper + " tail", "other words"], query: lower, k: 2)
            #expect(r2.map(\.index) == [0], "\(lower) should match \(upper)")
        }
    }

    @Test func foldsDeseretFourByteUppercase() throws {
        let r = try BM25.topK(chunks: ["𐐀𐐁𐐂 x", "none"], query: "𐐨𐐩𐐪", k: 2)
        #expect(r.map(\.index) == [0])
    }

    @Test func fullwidthLatinMatchesAscii() throws {
        let r = try BM25.topK(chunks: ["abc def", "zzz"], query: "ＡＢＣ", k: 2)
        #expect(r.map(\.index) == [0])
        let r2 = try BM25.topK(chunks: ["ＡＢＣ def", "zzz"], query: "abc", k: 2)
        #expect(r2.map(\.index) == [0])
    }

    @Test func invalidAndTruncatedUtf8DoNotCrash() throws {
        // Build chunks from raw bytes that end mid-sequence; String(decoding:) would repair them,
        // so drive the C API directly.
        let samples: [[UInt8]] = [
            [0x61, 0x62, 0x63, 0xE3], [0x61, 0x62, 0x63, 0xEF, 0xBC], [0x61, 0x62, 0x63, 0xF0, 0x90, 0x90],
            [0xFF, 0xFE, 0x61, 0x62, 0x63], [0xEF, 0xBC, 0x41, 0xEF, 0xBC],
        ]
        for bytes in samples {
            var heap = bytes
            let n = heap.count
            heap.withUnsafeMutableBufferPointer { bp in
                let p = UnsafeRawPointer(bp.baseAddress!).assumingMemoryBound(to: CChar.self)
                var spans = [lf_text_span(ptr: p, len: n)]
                let ix = lf_bm25_create(&spans, 1, 1.2, 0.75)
                var ids = [UInt32](repeating: 0, count: 1)
                var sc = [Double](repeating: 0, count: 1)
                if let ix {
                    _ = lf_bm25_query(ix, p, n, 1, &ids, &sc)
                    lf_bm25_free(ix)
                }
            }
        }
    }

    @Test func largeCorpusFindsNeedle() throws {
        var chunks = (0..<2000).map { "filler text number \($0) lorem ipsum" }
        chunks[1234] += " needleword"
        let r = try BM25.topK(chunks: chunks, query: "needleword", k: 1)
        #expect(r.map(\.index) == [1234])
    }

    // MARK: Chunker

    @Test func chunkerEmptyIsEmpty() {
        #expect(Chunker.chunks("").isEmpty)
        #expect(Chunker.chunks("\n\n  \n").isEmpty)
    }

    @Test func chunkerRespectsTwiceTarget() {
        let para = String(repeating: "word ", count: 60)
        let text = (0..<40).map { _ in para }.joined(separator: "\n\n")
        let target = 100
        let chunks = Chunker.chunks(text, targetTokens: target)
        #expect(chunks.count > 1)
        for c in chunks { #expect(TokenEstimator.estimate(c) <= 2 * target) }
        let joined = chunks.joined(separator: " ")
        #expect(joined.components(separatedBy: "word").count == text.components(separatedBy: "word").count)
    }

    @Test func chunkerKeepsSingleHugeParagraphWhole() {
        let huge = String(repeating: "word ", count: 5000)
        let chunks = Chunker.chunks(huge, targetTokens: 100)
        #expect(chunks.count == 1)
    }

    @Test func nonASCIIUppercaseQueryMatchesLowercaseChunk() throws {
        let chunks = ["la petite \u{00E9}cole du village", "nothing relevant here at all"]
        let r = try BM25.topK(chunks: chunks, query: "\u{00C9}COLE", k: 2)
        #expect(r.map(\.index) == [0])
    }

    @Test func nonASCIIUppercaseChunkMatchesLowercaseQuery() throws {
        let chunks = ["\u{041C}\u{041E}\u{0421}\u{041A}\u{0412}\u{0410} city", "other text entirely"]
        let r = try BM25.topK(chunks: chunks, query: "\u{043C}\u{043E}\u{0441}\u{043A}\u{0432}\u{0430}", k: 2)
        #expect(r.map(\.index) == [0])
    }
}
