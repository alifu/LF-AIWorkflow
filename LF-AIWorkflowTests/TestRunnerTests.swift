//
//  TestRunnerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.timeLimit(.minutes(3)))
struct TestRunnerTests {
    private let env = ["PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory()]

    /// Creates `files` (relative paths; a trailing `/` makes a directory) in a fresh temp dir.
    private func project(_ files: [String]) throws -> URL {
        let dir = try TestEnv.makeTempDir()
        for file in files {
            if file.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent(file), withIntermediateDirectories: true)
            } else {
                try TestEnv.write(dir, file, "x")
            }
        }
        return dir
    }

    private func display(_ files: [String]) throws -> String? {
        let dir = try project(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        return TestRunner.detect(in: dir)?.display
    }

    private func script(_ body: String) throws -> (dir: URL, command: TestCommand) {
        let dir = try TestEnv.makeTempDir()
        let url = try TestEnv.writeExecutable(dir, "t.sh", body: body)
        return (dir, TestCommand(executable: url, arguments: [], display: "t.sh"))
    }

    // MARK: detection

    @Test func detectsEachProjectType() throws {
        let table: [([String], String)] = [
            (["scripts/check.sh"], "scripts/check.sh"),
            (["gradlew"], "./gradlew check"),
            (["App.xcworkspace/"], "xcodebuild test -workspace App.xcworkspace -scheme App -destination platform=macOS"),
            (["App.xcodeproj/"], "xcodebuild test -project App.xcodeproj -scheme App -destination platform=macOS"),
            (["Package.swift"], "swift test"),
            (["package.json"], "npm test"),
            (["Cargo.toml"], "cargo test"),
            (["go.mod"], "go test ./..."),
            (["Makefile"], "make test"),
        ]
        for (files, expected) in table { #expect(try display(files) == expected, "\(files)") }
    }

    @Test func detectionPriority() throws {
        #expect(try display(["scripts/check.sh", "Package.swift"]) == "scripts/check.sh")
        #expect(try display(["gradlew", "App.xcodeproj/", "Package.swift"]) == "./gradlew check")
        #expect(try display(["A.xcodeproj/", "A.xcworkspace/", "Package.swift"])?.contains("-workspace") == true)
        #expect(try display(["Package.swift", "package.json"]) == "swift test")
        #expect(try display(["package.json", "Cargo.toml", "go.mod", "Makefile"]) == "npm test")
        #expect(try display(["Cargo.toml", "go.mod", "Makefile"]) == "cargo test")
        #expect(try display(["go.mod", "Makefile"]) == "go test ./...")
    }

    @Test func emptyDirectoryHasNoCommand() throws {
        #expect(try display([]) == nil)
        #expect(try display(["README.md"]) == nil)
    }

    @Test func schemeComesFromSharedSchemesSorted() throws {
        let files = ["App.xcodeproj/xcshareddata/xcschemes/Zeta.xcscheme", "App.xcodeproj/xcshareddata/xcschemes/Alpha.xcscheme"]
        #expect(try display(files)?.contains("-scheme Alpha ") == true)
    }

    @Test func nestedWorkspaceInsideProjectIsIgnored() throws {
        let files = ["App.xcodeproj/project.xcworkspace/contents.xcworkspacedata"]
        #expect(try display(files)?.contains("-project App.xcodeproj") == true)
    }

    @Test func nonExecutableCheckScriptRunsThroughSh() throws {
        let dir = try project(["scripts/check.sh"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = try #require(TestRunner.detect(in: dir))
        #expect(cmd.executable.path == "/bin/sh")
        #expect(cmd.arguments == ["scripts/check.sh"])
    }

    @Test func executableCheckScriptRunsDirectly() throws {
        let dir = try project([])
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        let script = try TestEnv.writeExecutable(dir.appendingPathComponent("scripts"), "check.sh", body: "exit 0")
        let cmd = try #require(TestRunner.detect(in: dir))
        #expect(cmd.executable.path == script.path)
    }

    @Test func detectionIgnoresAnyOverrideOnlyTheEngineSnapshotSuppliesOne() async throws {
        let dir = try project(["Package.swift"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = TestRunner(environment: env)
        #expect(await runner.detect(in: dir)?.display == "swift test")
    }

    // MARK: hardening

    @Test func strippedEnvironmentDropsCredentialsKeepsBasics() {
        let out = TestRunner.stripped([
            "PATH": "/usr/bin", "HOME": "/h", "LANG": "en_US.UTF-8", "SSH_AUTH_SOCK": "/s", "NPM_TOKEN": "t",
            "MY_SECRET": "s", "DB_PASSWORD": "p", "STRIPE_API_KEY": "k", "github_pat": "x", "GITHUB_TOKEN": "g",
            "AWS_REGION": "r", "ANTHROPIC_API_KEY": "a", "GH_HOST": "h",
        ])
        #expect(Set(out.keys) == ["PATH", "HOME", "LANG"])
    }

    @Test func runUsesStrippedEnvironment() async throws {
        let (dir, cmd) = try script("echo \"error: [$NPM_TOKEN][$SSH_AUTH_SOCK][$KEEP_ME]\"\nexit 1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let leaky = env.merging(["NPM_TOKEN": "hunter2", "SSH_AUTH_SOCK": "/sock", "KEEP_ME": "yes"]) { $1 }
        guard case .failed(_, let errors, _) = await TestRunner(environment: leaky).run(cmd, in: dir) else {
            Issue.record("expected failure"); return
        }
        #expect(errors.contains("error: [][][yes]"))
    }

    @Test func gitPushCannotSucceedFromATestRun() async throws {
        let remote = try TestEnv.makeTempDir()
        let repo = try await TestEnv.makeRepo()
        defer { try? FileManager.default.removeItem(at: remote); try? FileManager.default.removeItem(at: repo) }
        try await TestEnv.git(["init", "-q", "--bare", "-b", "main"], in: remote)
        try await TestEnv.git(["remote", "add", "origin", remote.path], in: repo)
        let push = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["push", "origin", "HEAD:main"], display: "git push")
        let runner = TestRunner(environment: TestEnv.git)
        guard case .failed = await runner.run(push, in: repo) else { Issue.record("push must fail"); return }
        await #expect(throws: (any Error).self) { try await TestEnv.git(["rev-parse", "--verify", "-q", "main"], in: remote) }
    }

    @Test func detectedCommandsNameTheirEntryPoint() throws {
        func entry(_ files: [String]) throws -> String? {
            let dir = try project(files)
            defer { try? FileManager.default.removeItem(at: dir) }
            return TestRunner.detect(in: dir)?.entryPoint
        }
        #expect(try entry(["scripts/check.sh"]) == "scripts/check.sh")
        #expect(try entry(["Makefile"]) == "Makefile")
        #expect(try entry(["Package.swift"]) == "Package.swift")
        #expect(try entry(["gradlew"]) == "gradlew")
        #expect(try entry(["App.xcodeproj/"]) == "App.xcodeproj/project.pbxproj")
    }

    // MARK: xcodebuild (TD-023)

    @Test func xcodebuildUsesOneOnlyTestingArgumentPerTarget() throws {
        let cmd = try TestRunner.xcodebuildCommand(container: URL(fileURLWithPath: "/r/App.xcodeproj"), scheme: "App",
                                                   onlyTesting: ["AppTests/A", "AppTests/B"])
        #expect(cmd.arguments.filter { $0.hasPrefix("-only-testing:") } == ["-only-testing:AppTests/A", "-only-testing:AppTests/B"])
        #expect(!cmd.arguments.contains { $0.contains(",") })
        #expect(!cmd.display.contains(","))
        let policy = StagePolicy.defaults(testCommand: cmd.display)
        #expect(throws: Never.self) {
            _ = try ClaudeCommandBuilder.arguments(config: policy.config(for: .code), sessionId: nil, addDirs: [])
        }
    }

    @Test func xcodebuildRejectsCommaTargets() {
        #expect(throws: WorkflowError.invalidTestTarget("A,B")) {
            _ = try TestRunner.xcodebuildCommand(container: URL(fileURLWithPath: "/r/App.xcodeproj"), scheme: "App",
                                                 onlyTesting: ["A,B"])
        }
    }

    // MARK: running

    @Test func exitZeroPasses() async throws {
        let (dir, cmd) = try script("exit 0")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(await TestRunner(environment: env).run(cmd, in: dir) == .passed)
    }

    @Test func failureCarriesExtractedErrors() async throws {
        let (dir, cmd) = try script("echo 'foo.swift:3: error: boom'\nexit 1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await TestRunner(environment: env).run(cmd, in: dir)
        guard case .failed(let status, let errors, _) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(status == 1)
        #expect(errors.contains("error: boom"))
        #expect(!errors.contains("\r"))
    }

    @Test func timeoutTerminatesTheProcessTree() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appendingPathComponent("pid")
        // `/bin/sh -c` instead of a fresh script file: the first exec of a new file can take seconds under load.
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                              arguments: ["-c", "echo $$ > \"\(pidFile.path)\"; sleep 30 & wait"], display: "sh")
        let runner = TestRunner(timeout: .milliseconds(500), environment: env)
        let start = ContinuousClock.now
        let outcome = await runner.run(cmd, in: dir)
        #expect(outcome == .timedOut)
        #expect(ContinuousClock.now - start < .seconds(4))
        let pid = try #require(try await TestEnv.readPid(pidFile))
        #expect(try await TestEnv.waitUntilGone(pid))
    }

    @Test func missingExecutableIsNotFound() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/nonexistent/lf-test-tool"), arguments: [], display: "x")
        #expect(await TestRunner(environment: env).run(cmd, in: dir) == .notFound)
    }

    @Test(arguments: ["lf-no-such-tool-xyz"]) func missingToolThroughEnvIsNotFound(tool: String) async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = TestCommand(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [tool, "test"], display: tool)
        #expect(await TestRunner(environment: env).run(cmd, in: dir) == .notFound)
    }

    @Test func status127FromOtherExecutableStaysFailed() async throws {
        let (dir, cmd) = try script("exit 127")
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .failed(let status, _, _) = await TestRunner(environment: env).run(cmd, in: dir) else {
            Issue.record("expected failed"); return
        }
        #expect(status == 127)
    }

    @Test func smallLogLimitKeepsTheNewestOutput() async throws {
        let (dir, cmd) = try script("""
        i=0; while [ $i -lt 2000 ]; do echo "noise line number $i ........................................"; i=$((i+1)); done
        echo 'tail.swift:9: error: tail marker'
        exit 1
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await TestRunner(maxLogBytes: 16 * 1024, environment: env).run(cmd, in: dir)
        guard case .failed(_, let errors, let truncated) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(errors.contains("tail marker"))
        #expect(truncated)
    }

    @Test func fortyMegabytesOfOutputFinishes() async throws {
        let (dir, cmd) = try script("/usr/bin/yes 'abcdefghijklmnopqrstuvwxyz0123456789 padding padding padding' | /usr/bin/head -c 41943040\nexit 0")
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await TestRunner(environment: env).run(cmd, in: dir)
        #expect(outcome == .passed)
    }
}
