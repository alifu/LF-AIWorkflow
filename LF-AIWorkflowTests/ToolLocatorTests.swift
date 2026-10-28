//
//  ToolLocatorTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ToolLocatorTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lf-tl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func makeFile(_ dir: URL, _ name: String, mode: Int = 0o755, body: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    }

    @Test func findsExecutableInSearchPath() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = try makeFile(dir, "claude")
        let url = try ToolLocator(searchPath: [dir.path]).locate(.claude)
        #expect(url.path == file.path)
    }

    @Test func skipsNonExecutableFile() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try makeFile(dir, "claude", mode: 0o644)
        #expect(throws: ToolLocatorError.notFound(.claude, searched: [dir.path])) {
            try ToolLocator(searchPath: [dir.path]).locate(.claude)
        }
    }

    @Test func firstDirectoryWins() throws {
        let a = try makeTempDir(), b = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try makeFile(a, "git"); try makeFile(b, "git")
        let url = try ToolLocator(searchPath: [a.path, b.path]).locate(.git)
        #expect(url.deletingLastPathComponent().path == a.path)
    }

    @Test func overrideWins() throws {
        let a = try makeTempDir(), b = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try makeFile(a, "graphify"); let custom = try makeFile(b, "my-graphify")
        let locator = ToolLocator(searchPath: [a.path], overrides: [.graphify: custom.path])
        #expect(try locator.locate(.graphify).path == custom.path)
    }

    @Test func invalidOverrideThrowsWithoutFallback() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try makeFile(dir, "claude")
        for bad in ["/nonexistent/claude", "relative/claude", dir.appendingPathComponent("claude").path + "x"] {
            let locator = ToolLocator(searchPath: [dir.path], overrides: [.claude: bad])
            #expect(throws: ToolLocatorError.overrideNotExecutable(.claude, path: bad)) { try locator.locate(.claude) }
        }
    }

    @Test func missingToolListsSearchedDirectories() {
        let locator = ToolLocator(searchPath: ["/a", "/b"], isExecutable: { _ in false })
        #expect(throws: ToolLocatorError.notFound(.git, searched: ["/a", "/b"])) { try locator.locate(.git) }
    }

    @Test func searchPathOrdersDedupsAndFilters() {
        let path = ToolLocator.searchPath(loginShellPATH: "/x/bin:rel/bin::/usr/bin:/x/bin:~/tools",
                                          processPATH: "/p/bin:/usr/bin", home: "/Users/h")
        #expect(path == ["/x/bin", "/usr/bin", "/Users/h/tools", "/p/bin", "/opt/homebrew/bin",
                         "/usr/local/bin", "/Users/h/.local/bin", "/bin"])
    }

    @Test func searchPathWithoutShellPathUsesDefaults() {
        let path = ToolLocator.searchPath(loginShellPATH: nil, processPATH: nil, home: "/Users/h")
        #expect(path == ["/opt/homebrew/bin", "/usr/local/bin", "/Users/h/.local/bin", "/usr/bin", "/bin"])
    }

    @Test(arguments: Tool.allCases)
    func errorDescriptionsAreUserFacing(tool: Tool) {
        let notFound = ToolLocatorError.notFound(tool, searched: ["/a", "/b"]).errorDescription ?? ""
        let override = ToolLocatorError.overrideNotExecutable(tool, path: "/x").errorDescription ?? ""
        #expect(!notFound.isEmpty && !override.isEmpty)
        #expect(!notFound.contains("/a"))
    }

    @Test func loginShellPathReturnsPath() async {
        let path = await LoginShellPath(shell: "/bin/sh").resolve()
        #expect(path?.contains("/usr/bin") == true)
    }

    @Test func loginShellPathIgnoresProfileNoise() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let script = try makeFile(dir, "noisy-sh", body: """
        #!/bin/sh
        echo "welcome banner"
        printf '__LFPATH__%s__LFPATH__' "/noise/bin:/usr/bin"
        echo "trailing noise"
        """)
        #expect(await LoginShellPath(shell: script.path).resolve() == "/noise/bin:/usr/bin")
    }

    @Test func loginShellPathNilForMissingShellOrFailure() async throws {
        #expect(await LoginShellPath(shell: "/nonexistent/shell").resolve() == nil)
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let failing = try makeFile(dir, "fail-sh", body: "#!/bin/sh\nexit 3\n")
        #expect(await LoginShellPath(shell: failing.path).resolve() == nil)
    }

    @Test func loginShellPathTimesOut() async throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let slow = try makeFile(dir, "slow-sh", body: "#!/bin/sh\nexec sleep 30\n")
        #expect(await LoginShellPath(shell: slow.path, timeout: .milliseconds(300)).resolve() == nil)
    }

    @Test func loginShellPathIsCached() async throws {
        let shell = LoginShellPath(shell: "/bin/sh")
        let first = await shell.resolve()
        #expect(await shell.resolve() == first)
    }
}
