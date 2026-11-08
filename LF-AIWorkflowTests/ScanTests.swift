//
//  ScanTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import LFCore
@testable import LF_AIWorkflow

/// Temp directory tree removed on deinit.
private final class TempTree {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "lfscan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit {
        // Restore permissions so removal succeeds.
        if let e = FileManager.default.enumerator(atPath: root.path) {
            for case let rel as String in e { chmod(root.appending(path: rel).path, 0o755) }
        }
        try? FileManager.default.removeItem(at: root)
    }
    @discardableResult
    func file(_ rel: String, _ data: Data = Data("x".utf8)) throws -> URL {
        let url = root.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    func names(_ files: [ScannedFile]) -> [String] {
        let base = root.resolvingSymlinksInPath().path + "/"
        return files.map { $0.path.replacingOccurrences(of: base, with: "") }.sorted()
    }
}

struct FNVTests {
    @Test(arguments: [("", UInt64(0xcbf29ce484222325)), ("a", 0xaf63dc4c8601ec8c), ("foobar", 0x85944171f73967e8)])
    func knownVectors(input: String, expected: UInt64) {
        let bytes = Array(input.utf8)
        #expect(lf_fnv1a64(bytes, bytes.count, UInt64(LF_FNV1A64_OFFSET)) == expected)
    }

    @Test func nullEmptyReturnsSeed() {
        #expect(lf_fnv1a64(nil, 0, 42) == 42)
    }

    @Test func chainedEqualsOneShot() {
        let bytes = Array("hello, chained world".utf8)
        let one = lf_fnv1a64(bytes, bytes.count, UInt64(LF_FNV1A64_OFFSET))
        let a = lf_fnv1a64(bytes, 7, UInt64(LF_FNV1A64_OFFSET))
        let b = bytes.withUnsafeBufferPointer { lf_fnv1a64($0.baseAddress! + 7, bytes.count - 7, a) }
        #expect(a != one)
        #expect(b == one)
    }

    @Test(arguments: [0, 1, 65_536, 65_537, 200 * 1024])
    func fileHashEqualsMemoryHashAtBufferBoundaries(size: Int) throws {
        let tree = try TempTree()
        let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let url = try tree.file("f.bin", data)
        var out: UInt64 = 0
        #expect(lf_fnv1a64_file(url.path, &out) == 0)
        let mem = data.withUnsafeBytes { lf_fnv1a64($0.baseAddress, $0.count, UInt64(LF_FNV1A64_OFFSET)) }
        #expect(out == mem)
    }

    @Test func fileHashErrors() {
        var out: UInt64 = 0
        errno = 0
        #expect(lf_fnv1a64_file("/nonexistent/lf-file", &out) == -1)
        #expect(errno == ENOENT)
        #expect(lf_fnv1a64_file(nil, &out) == -1)
    }

    @Test func fileHashRejectsFIFOWithoutHanging() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "lffifo-\(UUID().uuidString)").path
        #expect(mkfifo(path, 0o600) == 0)
        defer { unlink(path) }
        var out: UInt64 = 0
        errno = 0
        #expect(lf_fnv1a64_file(path, &out) == -1)
        #expect(errno == EINVAL)
    }

    @Test func fileHashRejectsSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lflink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appending(path: "t"), link = dir.appending(path: "l")
        try Data("x".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var out: UInt64 = 0
        errno = 0
        #expect(lf_fnv1a64_file(link.path, &out) == -1)
        #expect(errno == ELOOP)
    }
}

struct ScanTests {

    @Test func depthFilter() throws {
        let t = try TempTree()
        try t.file("a.txt"); try t.file("d1/b.txt"); try t.file("d1/d2/c.txt")
        let got = try FolderScanner.scan(t.root, options: .init(maxDepth: 2))
        #expect(t.names(got) == ["a.txt", "d1/b.txt"])
        #expect(try t.names(FolderScanner.scan(t.root)) == ["a.txt", "d1/b.txt", "d1/d2/c.txt"])
    }

    @Test func extensionFilterIsCaseInsensitive() throws {
        let t = try TempTree()
        try t.file("a.MD"); try t.file("b.md"); try t.file("c.txt"); try t.file("README"); try t.file("d.")
        let got = try FolderScanner.scan(t.root, options: .init(extensions: ["md"]))
        #expect(t.names(got) == ["a.MD", "b.md"])
    }

    @Test func hiddenSkippedByDefaultIncludedOnRequest() throws {
        let t = try TempTree()
        try t.file("v.txt"); try t.file(".hidden.txt"); try t.file(".git/config")
        #expect(try t.names(FolderScanner.scan(t.root)) == ["v.txt"])
        let all = try FolderScanner.scan(t.root, options: .init(includeHidden: true))
        #expect(t.names(all) == [".git/config", ".hidden.txt", "v.txt"])
    }

    @Test func symlinkLoopTerminatesWithoutReportingThroughLink() throws {
        let t = try TempTree()
        try t.file("a/f.txt")
        try FileManager.default.createSymbolicLink(
            at: t.root.appending(path: "a/loop"), withDestinationURL: t.root)
        let got = try FolderScanner.scan(t.root)
        #expect(t.names(got) == ["a/f.txt"])
    }

    @Test func symlinkToFileIsNotFollowed() throws {
        let t = try TempTree()
        let target = try t.file("real.txt")
        try FileManager.default.createSymbolicLink(at: t.root.appending(path: "link.txt"), withDestinationURL: target)
        #expect(try t.names(FolderScanner.scan(t.root)) == ["real.txt"])
    }

    @Test func emptyDirectoryYieldsNothing() throws {
        let t = try TempTree()
        #expect(try FolderScanner.scan(t.root).isEmpty)
    }

    @Test func missingRootFailsWithENOENT() {
        #expect(throws: LFCoreError.posix(ENOENT)) {
            try FolderScanner.scan(URL(filePath: "/nonexistent/lf-root"))
        }
        errno = 0
        #expect(lf_scan_walk(nil, nil, nil, nil) == -1)
        #expect(errno == EINVAL)
    }

    @Test func unreadableSubdirIsSkippedRestReported() throws {
        let t = try TempTree()
        try t.file("ok.txt"); try t.file("locked/x.txt")
        chmod(t.root.appending(path: "locked").path, 0o000)
        let got = try FolderScanner.scan(t.root)
        #expect(t.names(got) == ["ok.txt"])
    }

    @Test func maxHashBytesLeavesLargeFilesUnhashed() throws {
        let t = try TempTree()
        try t.file("small.txt", Data(repeating: 1, count: 10))
        try t.file("big.txt", Data(repeating: 2, count: 100))
        let got = try FolderScanner.scan(t.root, options: .init(maxHashBytes: 50))
        let byName = Dictionary(uniqueKeysWithValues: zip(t.names(got), got.sorted { $0.path < $1.path }))
        #expect(byName["small.txt"]?.hash != nil)
        #expect(byName["big.txt"]?.hash == nil)
        #expect(byName["big.txt"]?.size == 100)
    }

    @Test func hashMatchesContent() throws {
        let t = try TempTree()
        try t.file("a.txt", Data("foobar".utf8))
        let got = try FolderScanner.scan(t.root)
        #expect(got.first?.hash == 0x85944171f73967e8)
        #expect(got.first?.size == 6)
    }

    @Test func multibyteFileNameBytesSurviveInPathLen() throws {
        // APFS rejects non-UTF-8 names (EILSEQ), so a raw 0xFF name cannot be created here;
        // multibyte names still prove path_len counts bytes and not characters.
        let t = try TempTree()
        let dir = t.root.resolvingSymlinksInPath().path
        let raw = Array((dir + "/é日本😀.txt").utf8) + [0]
        let fd = raw.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { open($0, O_CREAT | O_WRONLY, 0o644) }
        }
        try #require(fd >= 0)
        close(fd)

        final class Sink { var paths: [[UInt8]] = [] }
        let sink = Sink()
        let cb: lf_scan_cb = { e, ctx in
            let s = Unmanaged<Sink>.fromOpaque(ctx!).takeUnretainedValue()
            let p = UnsafeRawBufferPointer(start: e!.pointee.path, count: e!.pointee.path_len)
            s.paths.append(Array(p))
            return 0
        }
        let n = withExtendedLifetime(sink) { lf_scan_walk(dir, nil, cb, Unmanaged.passUnretained(sink).toOpaque()) }
        #expect(n == 1)
        #expect(sink.paths == [Array(raw.dropLast())])
    }

    @Test func callbackStopHaltsAfterNEntries() throws {
        let t = try TempTree()
        for i in 0..<5 { try t.file("f\(i).txt") }
        final class Counter { var n = 0 }
        let c = Counter()
        let cb: lf_scan_cb = { _, ctx in
            let c = Unmanaged<Counter>.fromOpaque(ctx!).takeUnretainedValue()
            c.n += 1
            return c.n >= 2 ? 1 : 0
        }
        let n = withExtendedLifetime(c) { lf_scan_walk(t.root.path, nil, cb, Unmanaged.passUnretained(c).toOpaque()) }
        #expect(n == 2)
        #expect(c.n == 2)
    }

    @Test func rootIsADirectoryOnlyFilesCounted() throws {
        let t = try TempTree()
        try t.file("sub/a.txt")
        let got = try FolderScanner.scan(t.root)
        #expect(got.count == 1)
        #expect(Set(got).count == 1)
    }
}
