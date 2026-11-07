//
//  AppComposition.swift
//  LF-AIWorkflow
//

import Foundation

/// Stand-in when the bundled Safari scripts are missing: every call reports Safari as unavailable.
nonisolated struct UnavailableSafari: SafariControlling {
    func tabs() async throws(SafariError) -> [SafariTab] { throw .safariNotRunning }
    func currentTab() async throws(SafariError) -> SafariTab? { throw .safariNotRunning }
    func extract(_ tab: SafariTab) async throws(SafariError) -> CapturedPage { throw .safariNotRunning }
    func permission() async -> SafariPermissionState { .safariNotRunning }
}

/// Everything the Research tab and the inbox hotkey need.
@MainActor
struct ResearchServices {
    let viewModel: ResearchViewModel
    let composer: ResearchComposerViewModel
    let pipeline: ResearchPipeline
    let inbox: ResearchInbox
    let capture: InboxCapture
}

/// Both view-model graphs the app launches with.
@MainActor
struct AppServices {
    let model: WorkflowViewModel
    let research: ResearchServices
}

/// Builds the production engine, log store and view model (composition root).
@MainActor
enum AppComposition {
    /// The one settings store, shared by the notch panel's hosting view and the Settings scene (separate view trees).
    static let settings = SettingsStore()

    /// Where the daily token ledger lives: `~/Library/Application Support/LF-AIWorkflow/day-tokens.json`.
    static var ledgerURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LF-AIWorkflow", isDirectory: true).appendingPathComponent("day-tokens.json")
    }

    /// Where tasks are persisted: `~/Library/Application Support/LF-AIWorkflow/tasks.json`.
    static var tasksURL: URL? {
        ledgerURL?.deletingLastPathComponent().appendingPathComponent("tasks.json")
    }

    /// Where research tasks are persisted, next to `tasks.json`.
    static var researchURL: URL? {
        ledgerURL?.deletingLastPathComponent().appendingPathComponent("research.json")
    }

    /// The login-shell PATH (off the main actor, 5 s cap) merged with the process PATH and the install fallbacks.
    /// Complexity: O(d) time over PATH entries plus the login-shell run, O(d) space
    static func resolveSearchPath() async -> [String] {
        let loginPath = await LoginShellPath().resolve()
        let env = ProcessInfo.processInfo.environment
        return ToolLocator.searchPath(loginShellPATH: loginPath, processPATH: env["PATH"], home: NSHomeDirectory())
    }

    /// A provider that rebuilds the locator from the live Settings paths on every call. Reads the lock-backed mirror,
    /// so the call never hops to the MainActor.
    /// Complexity: O(1) time to build, O(k + d) time per call (k overrides copied, d search path), O(d) space
    static func liveLocators(searchPath: [String], paths: ToolPathStore) -> ToolLocatorProvider {
        ToolLocatorProvider { ToolLocator(searchPath: searchPath, overrides: paths.current) }
    }

    /// Wires the engine from one snapshot of the settings. The Claude, git and graphify clients ask the live locator
    /// per call, so a changed CLI path applies to the next task without a relaunch.
    /// Complexity: O(d) time over PATH entries plus the login-shell run (bounded by its 5 s timeout), O(d) space
    static func makeServices() async -> AppServices {
        let snapshot = settings.snapshot()
        let searchPath = await resolveSearchPath()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        let locators = liveLocators(searchPath: searchPath, paths: settings.toolPathStore)
        let engineSettings = EngineSettings.from(snapshot)
        let runner = LiveClaudeRunner(locators: locators, baseEnvironment: environment, searchPath: searchPath)
        let (claude, researchRunner): (any ClaudeStageRunning, any ResearchClaudeRunning) = (runner, runner)
        let git = GitClient(locators: locators, environment: environment)
        let logs = TaskLogStore()
        let ledger = DayTokenLedger(fileURL: Self.ledgerURL)
        let deps = EngineDependencies(
            claude: claude, tests: TestRunner(environment: environment),
            graph: GraphifyClient(locators: locators, environment: environment), git: git,
            worktrees: WorktreeManager(git: git), log: logs, ledger: ledger,
            store: tasksURL.map { ProjectStore(fileURL: $0) })
        let engine = WorkflowEngine(dependencies: deps, settings: engineSettings)
        await engine.restore()
        let model = WorkflowViewModel(engine: engine, logs: logs, fixLoopCap: engineSettings.fixLoopCap)
        model.start()
        let research = makeResearch(runner: researchRunner, snapshot: snapshot, ledger: ledger)
        await research.pipeline.restore()
        return AppServices(model: model, research: research)
    }

    /// The research day total: reads and feeds the same ledger as the Code engine, so both share one daily cap.
    /// With no ledger the total is 0 and spend is dropped.
    /// Complexity: O(1) time, O(1) space
    static func researchDayHooks(
        ledger: DayTokenLedger?
    ) -> (used: @Sendable () async -> Int, add: @Sendable (Int) async -> Void) {
        (used: { await ledger?.used() ?? 0 }, add: { await ledger?.add($0) })
    }

    /// Wires the research pipeline, view models and inbox. The store root comes from the settings
    /// (default `~/Documents/LF-AIWorkflow/Research`); the crawler uses the standard host policy.
    /// Complexity: O(1) time, O(1) space
    static func makeResearch(
        runner: any ResearchClaudeRunning, snapshot: SettingsSnapshot, ledger: DayTokenLedger?) -> ResearchServices {
        let root = settings.researchRoot
        let safari: any SafariControlling = SafariBridge.bundled() ?? UnavailableSafari()
        let policy = HostPolicy.standard
        let crawler = Crawler(
            renderer: WebPageRendering(renderer: WebPageRenderer(policy: policy)),
            robots: RobotsCache(fetcher: URLSessionRobotsFetcher(policy: policy), policy: policy),
            resolver: SystemHostResolver(), policy: policy, limiter: HostRateLimiter(clock: ContinuousClock()))
        let day = researchDayHooks(ledger: ledger)
        let deps = ResearchDependencies(
            safari: safari, crawler: crawler, runner: runner, store: ResearchStore(root: root),
            now: { Date() }, dayTokensUsed: day.used, recordDayTokens: day.add)
        let pipeline = ResearchPipeline(
            deps: deps, settings: ResearchSettings(snapshot: snapshot),
            persistence: researchURL.map { ResearchTaskStore(fileURL: $0) })
        let inbox = ResearchInbox(folder: root)
        let viewModel = ResearchViewModel(updates: pipeline.updates, controller: pipeline, inbox: inbox, hostPolicy: policy)
        viewModel.start()
        return ResearchServices(
            viewModel: viewModel, composer: ResearchComposerViewModel(safari: safari, research: viewModel),
            pipeline: pipeline, inbox: inbox, capture: InboxCapture(safari: safari, inbox: inbox))
    }
}
