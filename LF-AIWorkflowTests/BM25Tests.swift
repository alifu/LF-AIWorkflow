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
}
