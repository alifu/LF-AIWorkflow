//
//  GraphifyClientTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

@Suite(.serialized, .timeLimit(.minutes(2)))
struct GraphifyClientTests {
    /// Fake graphify: logs each call's argv (one arg per line, calls separated by `--`), `update` creates the graph.
    private struct Fake {
        let dir: URL; let root: URL; let log: URL; let locator: ToolLocator
    }

    private func makeFake(queryBody: String, updateBody: String? = nil, graphExists: Bool) throws -> Fake {
        let dir = try TestEnv.makeTempDir()
        let root = dir.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if graphExists { try TestEnv.write(root, "graphify-out/graph.json", "{}") }
        let log = dir.appendingPathComponent("argv.log")
        let update = updateBody ?? "mkdir -p \"$2/graphify-out\"; echo '{}' > \"$2/graphify-out/graph.json\""
        try TestEnv.writeExecutable(dir, "graphify", body: """
        { for a in "$@"; do echo "$a"; done; echo "--"; } >> "\(log.path)"
        case "$1" in
          update)
        \(update)
        ;;
          query)
        \(queryBody)
        ;;
        esac
        """)
        return Fake(dir: dir, root: root, log: log, locator: ToolLocator(searchPath: [dir.path]))
    }

    private func calls(_ fake: Fake) -> [[String]] {
        guard let text = try? String(contentsOf: fake.log, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "--\n").filter { !$0.isEmpty }
            .map { $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }

    private func fixtureText() throws -> String { String(decoding: try loadFixture("graphify_query_output.txt"), as: UTF8.self) }

    private func client(_ fake: Fake, queryTimeout: Duration = .seconds(60)) -> GraphifyClient {
        GraphifyClient(locator: fake.locator, queryTimeout: queryTimeout, updateTimeout: .seconds(60),
                       environment: ["PATH": "/usr/bin:/bin"])
    }

    @Test func parsesNodesFromFixture() throws {
        let nodes = GraphifyClient.parseNodes(try fixtureText())
        #expect(nodes.count == 12)
        #expect(nodes.first == GraphNode(label: "ClaudeSession", file: "LF-AIWorkflow/Claude/ClaudeSession.swift", line: 16))
        #expect(nodes.contains(GraphNode(label: ".start()", file: "LF-AIWorkflow/Claude/ClaudeSession.swift", line: 58)))
    }

    @Test func parseNodesIgnoresNonNodeLinesAndMissingAttributes() {
        let nodes = GraphifyClient.parseNodes("Traversal: x\nNODE Plain\nnot a node\nNODE A [src=a b/c.swift loc=L3 community=X]\n")
        #expect(nodes == [GraphNode(label: "Plain", file: nil, line: nil),
                          GraphNode(label: "A", file: "a b/c.swift", line: 3)])
    }

    @Test func presentGraphRunsOneQueryWithBudgetAndGraphPath() async throws {
        let fake = try makeFake(queryBody: "cat <<'EOF'\n\(try fixtureText())\nEOF", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let result = await client(fake).query("ClaudeSession", root: fake.root, budgetTokens: 777)
        let recorded = calls(fake)
        #expect(recorded.count == 1)
        #expect(recorded[0] == ["query", "ClaudeSession", "--budget", "777", "--graph",
                                fake.root.appendingPathComponent("graphify-out/graph.json").path])
        #expect(result.nodes.count == 12)
        #expect(result.text.contains("NODE ClaudeSession"))
    }

    @Test func missingGraphUpdatesThenQueries() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo [src=f.swift loc=L1]'", graphExists: false)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let result = await client(fake).query("Foo", root: fake.root, budgetTokens: 500)
        let recorded = calls(fake)
        #expect(recorded.map { $0[0] } == ["update", "query"])
        #expect(recorded.first == ["update", fake.root.path])
        #expect(!result.text.isEmpty)
        #expect(result.nodes.first?.label == "Foo")
    }

    @Test func failedUpdateYieldsEmptyWithoutSecondUpdate() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'", updateBody: "exit 1", graphExists: false)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let result = await client(fake).query("Foo", root: fake.root, budgetTokens: 500)
        #expect(result == .empty)
        #expect(calls(fake).map { $0[0] } == ["update"])
    }

    @Test func notInstalledYieldsEmpty() async throws {
        let dir = try TestEnv.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = GraphifyClient(locator: ToolLocator(searchPath: []), environment: ["PATH": "/usr/bin:/bin"])
        #expect(await c.query("x", root: dir, budgetTokens: 100) == .empty)
        await c.update(root: dir)
    }

    @Test func nonZeroQueryYieldsEmpty() async throws {
        let fake = try makeFake(queryBody: "echo oops >&2; exit 2", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        #expect(await client(fake).query("Foo", root: fake.root, budgetTokens: 500) == .empty)
    }

    @Test func slowQueryTimesOutToEmpty() async throws {
        let fake = try makeFake(queryBody: "sleep 30", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let start = ContinuousClock.now
        let result = await client(fake, queryTimeout: .milliseconds(300)).query("Foo", root: fake.root, budgetTokens: 500)
        #expect(result == .empty)
        #expect(ContinuousClock.now - start < .seconds(3.3))
    }

    @Test func concurrentQueriesOnMissingGraphUpdateOnce() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'",
                                updateBody: "sleep 0.5; mkdir -p \"$2/graphify-out\"; echo '{}' > \"$2/graphify-out/graph.json\"",
                                graphExists: false)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let c = client(fake)
        async let a = c.query("Foo", root: fake.root, budgetTokens: 100)
        async let b = c.query("Bar", root: fake.root, budgetTokens: 100)
        let (ra, rb) = await (a, b)
        #expect(!ra.text.isEmpty && !rb.text.isEmpty)
        #expect(calls(fake).filter { $0[0] == "update" }.count == 1)
    }

    @Test func questionWithMetacharactersIsOneArgument() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        let question = #"say "hi"; rm -rf / $(whoami) 'x'"#
        _ = await client(fake).query(question, root: fake.root, budgetTokens: 100)
        #expect(calls(fake).first?[1] == question)
    }

    @Test func leadingDashesInQueryAreStripped() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        _ = await client(fake).query("--budget 5 Foo", root: fake.root, budgetTokens: 100)
        let argv = try #require(calls(fake).first)
        #expect(argv[0] == "query")
        #expect(!argv[1].hasPrefix("-"))
        #expect(argv[1] == "budget 5 Foo")
    }

    @Test func allDashQueryIsSkipped() async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        #expect(await client(fake).query("---", root: fake.root, budgetTokens: 100) == .empty)
        #expect(calls(fake).isEmpty)
    }

    @Test(arguments: [(" --graph /x", "graph /x"), ("\t-x", "x"), (" - -x", "x")])
    func whitespaceAndDashesAreStrippedUntilStable(input: String, expected: String) async throws {
        let fake = try makeFake(queryBody: "echo 'NODE Foo'", graphExists: true)
        defer { try? FileManager.default.removeItem(at: fake.dir) }
        _ = await client(fake).query(input, root: fake.root, budgetTokens: 100)
        let argv = try #require(calls(fake).first)
        #expect(argv[1] == expected)
    }
}
