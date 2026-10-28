//
//  SafariBridge.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum SafariError: Error, Sendable, Equatable {
    case automationDenied, javascriptFromAppleEventsOff, safariNotRunning
    case tabChanged, timedOut, outputTooLarge, malformedOutput
}

nonisolated struct SafariTab: Sendable, Equatable, Decodable {
    let window: Int
    let tab: Int
    let title: String
    let url: URL
    let current: Bool

    private enum CodingKeys: String, CodingKey { case window, tab, title, url, current }

    init(window: Int, tab: Int, title: String, url: URL, current: Bool) {
        self.window = window; self.tab = tab; self.title = title; self.url = url; self.current = current
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        window = try c.decode(Int.self, forKey: .window)
        tab = try c.decode(Int.self, forKey: .tab)
        title = try c.decode(String.self, forKey: .title)
        current = try c.decode(Bool.self, forKey: .current)
        guard let u = URL(string: try c.decode(String.self, forKey: .url)) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "bad url")
        }
        url = u
    }
}

protocol SafariControlling: Sendable {
    func tabs() async throws(SafariError) -> [SafariTab]
    func currentTab() async throws(SafariError) -> SafariTab?
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage
    func permission() async -> SafariPermissionState
}

nonisolated enum SafariBridgeParser {
    /// Decodes `list` output; only http(s) tabs survive.
    /// Complexity: O(n) time, O(n) space
    static func parseTabs(_ data: Data) throws(SafariError) -> [SafariTab] {
        guard let all = try? JSONDecoder().decode([SafariTab].self, from: data) else { throw .malformedOutput }
        return all.filter { ["http", "https"].contains($0.url.scheme?.lowercased()) }
    }

    /// Maps osascript stderr to a case; unknown text is `malformedOutput`.
    /// Complexity: O(n) time, O(n) space
    static func classify(stderr: Data) -> SafariError {
        let text = String(decoding: stderr, as: UTF8.self)
        if text.contains("-1743") { return .automationDenied }
        if text.contains("Allow JavaScript from Apple Events") { return .javascriptFromAppleEventsOff }
        if text.contains("-600") { return .safariNotRunning }
        if text.contains("tabChanged") { return .tabChanged }
        return .malformedOutput
    }
}

/// Reads tabs from Safari through `osascript -l JavaScript` with argv-only arguments.
nonisolated struct SafariBridge: SafariControlling {
    typealias Runner = @Sendable (ProcessInvocation, Duration, Int) async throws(CommandError) -> CommandResult

    static let maxOutputBytes = 4 << 20
    static let listTimeout: Duration = .seconds(10)
    static let extractTimeout: Duration = .seconds(30)
    static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    let scriptURL: URL
    let extractScriptURL: URL
    let runner: Runner

    init(scriptURL: URL, extractScriptURL: URL,
         runner: @escaping Runner = { inv, timeout, cap throws(CommandError) in
             try await CommandRunner.run(inv, timeout: timeout, maxOutputBytes: cap)
         }) {
        self.scriptURL = scriptURL
        self.extractScriptURL = extractScriptURL
        self.runner = runner
    }

    /// Bridge using the scripts bundled in the app; nil when a resource is missing.
    static func bundled(bundle: Bundle = .main) -> SafariBridge? {
        guard let script = bundle.url(forResource: "safari-bridge", withExtension: "js"),
              let extract = bundle.url(forResource: "extract", withExtension: "js") else { return nil }
        return SafariBridge(scriptURL: script, extractScriptURL: extract)
    }

    /// Complexity: O(n) time, O(n) space (n = output bytes, capped)
    func tabs() async throws(SafariError) -> [SafariTab] {
        try SafariBridgeParser.parseTabs(try await invoke(["list"], timeout: Self.listTimeout))
    }

    /// Complexity: O(n) time, O(n) space
    func currentTab() async throws(SafariError) -> SafariTab? {
        try await tabs().first(where: \.current)
    }

    /// Complexity: O(n) time, O(n) space
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage {
        let out = try await invoke(["extract", String(tab.window), String(tab.tab), tab.url.absoluteString,
                                    extractScriptURL.path], timeout: Self.extractTimeout)
        guard let page = try? CapturedPage.parse(String(decoding: out, as: UTF8.self)) else { throw .malformedOutput }
        return page
    }

    func permission() async -> SafariPermissionState { SafariPermission.current() }

    private func invoke(_ args: [String], timeout: Duration) async throws(SafariError) -> Data {
        let inv = ProcessInvocation(
            executable: Self.osascript, arguments: ["-l", "JavaScript", scriptURL.path] + args,
            environment: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()],
            workingDirectory: FileManager.default.temporaryDirectory, stdin: Data())
        let result: CommandResult
        do { result = try await runner(inv, timeout, Self.maxOutputBytes) } catch {
            switch error {
            case .timedOut: throw .timedOut
            case .spawnFailed: throw .malformedOutput
            }
        }
        if result.truncated { throw .outputTooLarge }
        guard result.status == 0 else { throw SafariBridgeParser.classify(stderr: result.stderr) }
        return result.stdout
    }
}
