//
//  EditorOpenerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@MainActor
final class SpyURLOpener: URLOpening {
    private(set) var opened: [URL] = []
    private(set) var revealed: [URL] = []
    var result = true
    func open(_ url: URL) -> Bool { opened.append(url); return result }
    func reveal(_ url: URL) { revealed.append(url) }
}

@Suite struct PathContainmentTests {
    private func makeRoot() throws -> URL {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "src/Theme.kt", "x")
        try TestEnv.write(root, "-rf", "x")
        return root
    }

    @Test func resolvesRelativeFileInside() throws {
        let root = try makeRoot()
        let url = PathContainment.resolve("src/Theme.kt", within: root)
        #expect(url?.lastPathComponent == "Theme.kt")
        #expect(url?.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") == true)
    }

    @Test func resolvesAbsolutePathInside() throws {
        let root = try makeRoot()
        #expect(PathContainment.resolve(root.appendingPathComponent("src/Theme.kt").path, within: root) != nil)
    }

    @Test func rejectsParentTraversal() throws {
        let root = try makeRoot()
        #expect(PathContainment.resolve("../../.ssh/config", within: root) == nil)
        #expect(PathContainment.resolve("src/../src/Theme.kt", within: root) == nil)
        #expect(PathContainment.resolve("..", within: root) == nil)
    }

    @Test func rejectsAbsolutePathOutside() throws {
        let root = try makeRoot()
        #expect(PathContainment.resolve("/etc/hosts", within: root) == nil)
    }

    @Test func rejectsSiblingWithSharedPrefix() throws {
        let root = try makeRoot()
        let sibling = URL(fileURLWithPath: root.path + "-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try "x".write(to: sibling.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        #expect(PathContainment.resolve(sibling.appendingPathComponent("a.txt").path, within: root) == nil)
    }

    @Test func rejectsLeadingDashEmptyAndNul() throws {
        let root = try makeRoot()
        #expect(PathContainment.resolve("-rf", within: root) == nil)
        #expect(PathContainment.resolve("--editor=evil", within: root) == nil)
        #expect(PathContainment.resolve("", within: root) == nil)
        #expect(PathContainment.resolve("   ", within: root) == nil)
        #expect(PathContainment.resolve("src/Theme.kt\0.png", within: root) == nil)
    }

    @Test func rejectsSymlinkEscapingTheRoot() throws {
        let root = try makeRoot()
        let outside = try TestEnv.makeTempDir()
        try TestEnv.write(outside, "secret.txt", "s")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.txt"),
                                                   withDestinationURL: outside.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dirlink"), withDestinationURL: outside)
        #expect(PathContainment.resolve("link.txt", within: root) == nil)
        #expect(PathContainment.resolve("dirlink/secret.txt", within: root) == nil)
    }

    @Test func rejectsMissingFile() throws {
        let root = try makeRoot()
        #expect(PathContainment.resolve("src/Nope.kt", within: root) == nil)
    }
}

@MainActor
@Suite struct EditorOpenerTests {
    @Test func opensContainedFileThroughTheBackend() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "a.swift", "x")
        let spy = SpyURLOpener()
        let ok = EditorOpener(backend: spy).open(path: "a.swift", line: 3, within: root)
        #expect(ok)
        #expect(spy.opened.map(\.lastPathComponent) == ["a.swift"])
    }

    @Test func refusesEscapesWithoutCallingTheBackend() throws {
        let root = try TestEnv.makeTempDir()
        let spy = SpyURLOpener()
        let opener = EditorOpener(backend: spy)
        #expect(!opener.open(path: "../../.ssh/config", line: nil, within: root))
        #expect(!opener.open(path: "/etc/hosts", line: nil, within: root))
        #expect(!opener.open(path: "-x", line: nil, within: root))
        #expect(spy.opened.isEmpty)
    }

    @Test func reportsBackendFailure() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "a.swift", "x")
        let spy = SpyURLOpener()
        spy.result = false
        #expect(!EditorOpener(backend: spy).open(path: "a.swift", line: nil, within: root))
    }

    // MARK: dangerous targets

    private func openAndRevealed(_ name: String, in root: URL) -> (ok: Bool, opened: [URL], revealed: [URL]) {
        let spy = SpyURLOpener()
        let ok = EditorOpener(backend: spy).open(path: name, line: nil, within: root)
        return (ok, spy.opened, spy.revealed)
    }

    @Test(arguments: ["run.command", "x.terminal", "Run.COMMAND", "a.pkg", "a.dmg", "a.workflow", "a.scpt", "a.applescript",
                      "a.jar", "a.webloc", "a.url", "a.sh", "noext"])
    func revealsInsteadOfOpeningRiskyOrUnknownTypes(name: String) throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, name, "x")
        let result = openAndRevealed(name, in: root)
        #expect(result.opened.isEmpty)
        #expect(result.revealed.map(\.lastPathComponent) == [name])
    }

    @Test func revealsAppBundleDirectoryAndPlainDirectory() throws {
        let root = try TestEnv.makeTempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Foo.app/Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        for name in ["Foo.app", "src"] {
            let result = openAndRevealed(name, in: root)
            #expect(result.opened.isEmpty)
            #expect(result.revealed.count == 1)
        }
    }

    @Test func revealsExecutableEvenWithAllowedExtension() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "tool.py", "print(1)")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("tool.py").path)
        let result = openAndRevealed("tool.py", in: root)
        #expect(result.opened.isEmpty)
        #expect(result.revealed.count == 1)
    }

    @Test func neverOpensAFifo() throws {
        let root = try TestEnv.makeTempDir()
        #expect(mkfifo(root.appendingPathComponent("pipe.txt").path, 0o644) == 0)
        let result = openAndRevealed("pipe.txt", in: root)
        #expect(result.opened.isEmpty)
    }

    @Test func refusesLeadingDash() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "-a.swift", "x")
        let result = openAndRevealed("-a.swift", in: root)
        #expect(!result.ok)
        #expect(result.opened.isEmpty && result.revealed.isEmpty)
    }

    @Test(arguments: ["a.swift", "a.c", "a.h", "a.m", "a.md", "a.txt", "a.json", "a.yml", "a.yaml", "a.toml", "a.js", "a.ts",
                      "a.tsx", "a.jsx", "a.py", "a.rb", "a.go", "a.rs", "a.kt", "a.java", "a.css", "A.SWIFT"])
    func opensAllowedRegularFiles(name: String) throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, name, "x")
        let result = openAndRevealed(name, in: root)
        #expect(result.ok)
        #expect(result.opened.count == 1)
        #expect(result.revealed.isEmpty)
    }

    /// The default handler for these is a browser, which can run local scripts, so they are reveal-only.
    @Test(arguments: ["a.html", "a.htm", "a.svg"])
    func revealsBrowserHandledTypesInsteadOfOpening(name: String) throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, name, "<script>alert(1)</script>")
        let result = openAndRevealed(name, in: root)
        #expect(result.ok)
        #expect(result.opened.isEmpty)
        #expect(result.revealed.count == 1)
    }

    // MARK: TOCTOU

    @Test func refusesWhenTheFileIsSwappedForAnEscapingSymlinkBeforeOpening() throws {
        let root = try TestEnv.makeTempDir()
        let outside = try TestEnv.makeTempDir()
        try TestEnv.write(outside, "evil.command", "x")
        try TestEnv.write(root, "a.swift", "x")
        let spy = SpyURLOpener()
        let target = root.appendingPathComponent("a.swift")
        let opener = EditorOpener(backend: spy, beforeOpen: { _ in
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside.appendingPathComponent("evil.command"))
        })
        #expect(!opener.open(path: "a.swift", line: nil, within: root))
        #expect(spy.opened.isEmpty)
    }

    @Test func downgradesToRevealWhenTheFileBecomesExecutableBeforeOpening() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "a.swift", "x")
        let target = root.appendingPathComponent("a.swift")
        let spy = SpyURLOpener()
        let opener = EditorOpener(backend: spy, beforeOpen: { _ in
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        })
        _ = opener.open(path: "a.swift", line: nil, within: root)
        #expect(spy.opened.isEmpty)
    }

    @Test func opensTheSymlinkResolvedURL() throws {
        let root = try TestEnv.makeTempDir()
        try TestEnv.write(root, "real.swift", "x")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.swift"),
                                                   withDestinationURL: root.appendingPathComponent("real.swift"))
        let spy = SpyURLOpener()
        #expect(EditorOpener(backend: spy).open(path: "link.swift", line: nil, within: root))
        #expect(spy.opened.map(\.lastPathComponent) == ["real.swift"])
    }
}
