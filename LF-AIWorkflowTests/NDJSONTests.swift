//
//  NDJSONTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

private func fixture(_ name: String) throws -> Data { try loadFixture(name) }

private func text(_ lines: [Data]) -> [String] { lines.map { String(decoding: $0, as: UTF8.self) } }

struct NDJSONTests {

    @Test func emptyFeedEmitsNothing() throws {
        let fr = try NDJSONFramer()
        #expect(try fr.feed(Data()).isEmpty)
        #expect(try fr.finish().isEmpty)
    }

    @Test func oneLineInOneChunk() throws {
        let fr = try NDJSONFramer()
        #expect(text(try fr.feed(Data("{\"a\":1}\n".utf8))) == ["{\"a\":1}"])
    }

    @Test func lineSplitAcrossTwoChunks() throws {
        let fr = try NDJSONFramer()
        #expect(try fr.feed(Data("{\"a\"".utf8)).isEmpty)
        #expect(text(try fr.feed(Data(":1}\n".utf8))) == ["{\"a\":1}"])
    }

    @Test func lineSplitAcrossThreeChunksIncludingBeforeNewline() throws {
        let fr = try NDJSONFramer()
        #expect(try fr.feed(Data("ab".utf8)).isEmpty)
        #expect(try fr.feed(Data("cd".utf8)).isEmpty)
        #expect(text(try fr.feed(Data("\n".utf8))) == ["abcd"])
    }

    @Test func crlfSplitBetweenCRAndLF() throws {
        let fr = try NDJSONFramer()
        #expect(try fr.feed(Data("abc\r".utf8)).isEmpty)
        #expect(text(try fr.feed(Data("\nnext\r\n".utf8))) == ["abc", "next"])
    }

    @Test func innerCarriageReturnIsKept() throws {
        let fr = try NDJSONFramer()
        #expect(text(try fr.feed(Data("a\rb\n".utf8))) == ["a\rb"])
    }

    @Test func blankLinesAreSkipped() throws {
        let fr = try NDJSONFramer()
        #expect(try fr.feed(Data("\n\n\n  \t\n\r\n".utf8)).isEmpty)
    }

    @Test func manyLinesInOneChunk() throws {
        let fr = try NDJSONFramer()
        let input = (0..<500).map { "{\"i\":\($0)}" }.joined(separator: "\n") + "\n"
        let out = text(try fr.feed(Data(input.utf8)))
        #expect(out.count == 500)
        #expect(out.last == "{\"i\":499}")
    }

    @Test(arguments: [1, 2, 5, 64])
    func chunkedFeedEqualsOneShot(chunk: Int) throws {
        let data = try fixture("stream.ndjson")
        let oneShot = try NDJSONFramer()
        let expected = try oneShot.feed(data)
        #expect(expected.count == 3)
        let fr = try NDJSONFramer()
        var got: [Data] = []
        var i = 0
        while i < data.count {
            got += try fr.feed(data.subdata(in: i..<min(i + chunk, data.count)))
            i += chunk
        }
        #expect(got == expected)
    }

    @Test func unterminatedFinalLineOnlyViaFinish() throws {
        let fr = try NDJSONFramer()
        #expect(text(try fr.feed(Data("a\nb".utf8))) == ["a"])
        #expect(text(try fr.finish()) == ["b"])
        #expect(try fr.finish().isEmpty)
    }

    @Test func oneMiBLineInFourKiBChunksArrivesIntact() throws {
        let fr = try NDJSONFramer()
        let line = Data(repeating: 0x61, count: 1 << 20)
        var got: [Data] = []
        var i = 0
        while i < line.count {
            got += try fr.feed(line.subdata(in: i..<(i + 4096)))
            i += 4096
        }
        got += try fr.feed(Data("\n".utf8))
        #expect(got == [line])
    }

    @Test func oversizeLineDroppedAndResyncs() throws {
        let fr = try NDJSONFramer(maxLine: 64)
        let big = String(repeating: "x", count: 200)
        #expect(text(try fr.feed(Data("\(big)\nok\n".utf8))) == ["ok"])
        #expect(fr.oversizeCount == 1)
    }

    @Test func oversizeLineSplitAcrossChunksDropsAndResyncs() throws {
        let fr = try NDJSONFramer(maxLine: 64)
        #expect(try fr.feed(Data(String(repeating: "x", count: 100).utf8)).isEmpty)
        #expect(try fr.feed(Data(String(repeating: "y", count: 100).utf8)).isEmpty)
        #expect(text(try fr.feed(Data("z\nok\n".utf8))) == ["ok"])
        #expect(fr.oversizeCount == 1)
    }

    @Test func oversizeJoinedWithPendingIsDropped() throws {
        let fr = try NDJSONFramer(maxLine: 64)
        #expect(try fr.feed(Data(String(repeating: "x", count: 40).utf8)).isEmpty)
        #expect(text(try fr.feed(Data((String(repeating: "y", count: 40) + "\nok\n").utf8))) == ["ok"])
        #expect(fr.oversizeCount == 1)
    }

    @Test func oversizeUnterminatedTailIsNotFlushedByFinish() throws {
        let fr = try NDJSONFramer(maxLine: 8)
        #expect(try fr.feed(Data(String(repeating: "x", count: 50).utf8)).isEmpty)
        #expect(try fr.finish().isEmpty)
        #expect(text(try fr.feed(Data("ok\n".utf8))) == ["ok"])
    }

    @Test func invalidUTF8PassesThroughVerbatim() throws {
        let fr = try NDJSONFramer()
        let line = Data([0x7B, 0xFF, 0xFE, 0x00, 0x7D])
        #expect(try fr.feed(line + Data("\n".utf8)) == [line])
    }

    @Test func callbackStopKeepsRemainingLinesForNextFeed() throws {
        let fr = try #require(lf_ndjson_create(0))
        defer { lf_ndjson_destroy(fr) }
        final class Seen { var lines: [String] = [] }
        let seen = Seen()
        let stopAfterFirst: lf_ndjson_line_cb = { line, len, ctx in
            let s = Unmanaged<Seen>.fromOpaque(ctx!).takeUnretainedValue()
            s.lines.append(String(decoding: UnsafeRawBufferPointer(start: line, count: len), as: UTF8.self))
            return 1
        }
        let input = Array("a\nb\nc\npart".utf8)
        let ctx = Unmanaged.passUnretained(seen).toOpaque()
        let first = withExtendedLifetime(seen) { lf_ndjson_feed(fr, input, input.count, stopAfterFirst, ctx) }
        #expect(first == 1)
        #expect(seen.lines == ["a"])
        let more = Array("ial\n".utf8)
        let second = withExtendedLifetime(seen) { lf_ndjson_feed(fr, more, more.count, stopAfterFirst, ctx) }
        #expect(second == 1)
        #expect(seen.lines == ["a", "b"])
        let rest = withExtendedLifetime(seen) { lf_ndjson_feed(fr, nil, 0, nil, nil) }
        #expect(rest == 2)   // nil callback drains "c" and "partial"
        #expect(lf_ndjson_feed(fr, nil, 0, nil, nil) == 0)
    }

    @Test func nullHandleFailsWithEINVAL() {
        errno = 0
        #expect(lf_ndjson_feed(nil, nil, 0, nil, nil) == -1)
        #expect(errno == EINVAL)
        #expect(lf_ndjson_finish(nil, nil, nil) == -1)
        #expect(lf_ndjson_oversize_count(nil) == 0)
        lf_ndjson_destroy(nil)
    }
}

struct NDJSONFieldTests {

    private func line(_ s: String) -> Data { Data(s.utf8) }

    @Test func typeFromFixtureLines() throws {
        let fr = try NDJSONFramer()
        let lines = try fr.feed(try fixture("stream.ndjson"))
        #expect(lines.map { NDJSONFramer.field("type", in: $0) } == ["system", "assistant", "result"])
        #expect(NDJSONFramer.field("subtype", in: lines[0]) == "init")
        #expect(NDJSONFramer.intField("message.usage.input_tokens", in: lines[1]) == 12)
        #expect(NDJSONFramer.intField("message.usage.output_tokens", in: lines[1]) == 34)
        #expect(NDJSONFramer.intField("usage.output_tokens", in: lines[2]) == 200)
        #expect(NDJSONFramer.intField("usage.cache_read_input_tokens", in: lines[2]) == 0)
    }

    @Test func keyInsideStringValueIsNotMatched() {
        let l = line(#"{"text":"\"type\":\"fake\"","type":"real"}"#)
        #expect(NDJSONFramer.field("type", in: l) == "real")
    }

    @Test func nestedKeyIsNotMatchedAtTopLevel() {
        let l = line(#"{"a":{"type":"inner"},"b":[{"type":"arr"}]}"#)
        #expect(NDJSONFramer.field("type", in: l) == nil)
        #expect(NDJSONFramer.field("a.type", in: l) == "inner")
    }

    @Test func escapedQuotesAndBackslashesInValues() {
        let l = line(#"{"x":"a\\","y":"q\"uote","type":"ok"}"#)
        #expect(NDJSONFramer.field("y", in: l) == #"q\"uote"#)
        #expect(NDJSONFramer.field("type", in: l) == "ok")
    }

    @Test func whitespaceAroundColon() {
        let l = line("{ \"type\" \t:\n  \"spaced\" , \"n\" : -42 }")
        #expect(NDJSONFramer.field("type", in: l) == "spaced")
        #expect(NDJSONFramer.intField("n", in: l) == -42)
    }

    @Test func arraysBeforeKeyAreSkipped() {
        let l = line(#"{"list":[1,{"type":"no"},"]}",[2]],"type":"yes"}"#)
        #expect(NDJSONFramer.field("type", in: l) == "yes")
    }

    @Test func missingKeyIsENOENT() {
        let l = Array(#"{"a":1}"#.utf8).map { CChar(bitPattern: $0) }
        var out: UnsafePointer<CChar>?
        var n = 0
        errno = 0
        #expect(lf_ndjson_get_string(l, l.count, "type", &out, &n) == -1)
        #expect(errno == ENOENT)
        var v: Int64 = 0
        #expect(lf_ndjson_get_int64(l, l.count, "a.b", &v) == -1)
        #expect(errno == ENOENT)
    }

    @Test func wrongTypeIsEINVAL() {
        let l = Array(#"{"a":"str","b":5,"c":1.5}"#.utf8).map { CChar(bitPattern: $0) }
        var v: Int64 = 0
        var out: UnsafePointer<CChar>?
        var n = 0
        #expect(lf_ndjson_get_int64(l, l.count, "a", &v) == -1)
        #expect(errno == EINVAL)
        #expect(lf_ndjson_get_string(l, l.count, "b", &out, &n) == -1)
        #expect(errno == EINVAL)
        #expect(lf_ndjson_get_int64(l, l.count, "c", &v) == -1)
        #expect(errno == EINVAL)
    }

    @Test func int64Limits() {
        var v: Int64 = 0
        func get(_ json: String) -> (Int32, Int64) {
            let l = Array(json.utf8).map { CChar(bitPattern: $0) }
            errno = 0
            let r = lf_ndjson_get_int64(l, l.count, "n", &v)
            return (r == 0 ? 0 : errno, v)
        }
        #expect(get(#"{"n":9223372036854775807}"#) == (0, Int64.max))
        #expect(get(#"{"n":-9223372036854775808}"#) == (0, Int64.min))
        #expect(get(#"{"n":9223372036854775808}"#).0 == ERANGE)
        #expect(get(#"{"n":-9223372036854775809}"#).0 == ERANGE)
        #expect(get(#"{"n":-7}"#) == (0, -7))
        #expect(get(#"{"n":-}"#).0 == EINVAL)
    }

    @Test(arguments: ["", "{", #"{"type":"res"#, #"{"type""#, #"{"type":"#, #"{"a":[1,2"#, "not json", #"{"a" 1}"#])
    func truncatedOrMalformedLinesDoNotCrash(json: String) {
        let l = Data(json.utf8)
        #expect(NDJSONFramer.field("type", in: l) == nil)
        #expect(NDJSONFramer.intField("type", in: l) == nil)
    }

    @Test func invalidArgumentsAreEINVAL() {
        var out: UnsafePointer<CChar>?
        var n = 0
        errno = 0
        #expect(lf_ndjson_get_string("{}", 2, "", &out, &n) == -1)
        #expect(errno == EINVAL)
        #expect(lf_ndjson_get_int64("{}", 2, "a", nil) == -1)
    }
}
