//
//  AppComposition.swift
//  LF-AIWorkflow
//

import Foundation

/// Stand-in runner when the Claude CLI cannot be found: every stage fails with the locator's message.
nonisolated struct UnavailableClaudeRunner: ClaudeStageRunning {
    let error: ToolLocatorError

    func run(_ request: StageRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

extension UnavailableClaudeRunner: ResearchClaudeRunning {
    func run(_ request: ResearchRunRequest) -> AsyncThrowingStream<StageRunEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

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

    /// The login-shell PATH (off the main actor, 5 s cap) merged with the process PATH and the install fallbacks.
    /// Complexity: O(d) time over PATH entries plus the login-shell run, O(d) space
    static func resolveSearchPath() async -> [String] {
        let loginPath = await LoginShellPath().resolve()
        let env = ProcessInfo.processInfo.environment
        return ToolLocator.searchPath(loginShellPATH: loginPath, processPATH: env["PATH"], home: NSHomeDirectory())
    }

    /// Locates the tools (with the Settings overrides) and wires the engine from one snapshot of the settings.
    /// Tool paths are read here only: a changed CLI path takes effect after the next launch.
    /// Complexity: O(d) time over PATH entries plus the login-shell run (bounded by its 5 s timeout), O(d) space
    static func makeServices() async -> AppServices {
        let snapshot = settings.snapshot()
        let searchPath = await resolveSearchPath()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        let locator = ToolLocator(searchPath: searchPath, overrides: snapshot.toolPaths)
        let engineSettings = EngineSettings.from(snapshot)
        let claude: any ClaudeStageRunning
        let researchRunner: any ResearchClaudeRunning
        do {
            let runner = ClaudeStageRunner(executable: try locator.locate(.claude), baseEnvironment: environment, searchPath: searchPath)
            (claude, researchRunner) = (runner, runner)
        } catch {
            let unavailable = UnavailableClaudeRunner(error: error)
            (claude, researchRunner) = (unavailable, unavailable)
        }
        let git = GitClient(locator: locator, environment: environment)
        let logs = TaskLogStore()
        let deps = EngineDependencies(
            claude: claude, tests: TestRunner(override: engineSettings.testCommandOverride, environment: environment),
            graph: GraphifyClient(locator: locator, environment: environment), git: git,
            worktrees: WorktreeManager(git: git), log: logs)
        let engine = WorkflowEngine(dependencies: deps, settings: engineSettings)
        let model = WorkflowViewModel(engine: engine, logs: logs, fixLoopCap: engineSettings.fixLoopCap)
        model.start()
        return AppServices(model: model, research: makeResearch(runner: researchRunner, snapshot: snapshot))
    }

    /// Wires the research pipeline, view models and inbox. The store root comes from the settings
    /// (default `~/Documents/LF-AIWorkflow/Research`); the crawler uses the standard host policy.
    /// Complexity: O(1) time, O(1) space
    static func makeResearch(runner: any ResearchClaudeRunning, snapshot: SettingsSnapshot) -> ResearchServices {
        let root = settings.researchRoot
        let safari: any SafariControlling = SafariBridge.bundled() ?? UnavailableSafari()
        let policy = HostPolicy.standard
        let crawler = Crawler(
            renderer: WebPageRendering(renderer: WebPageRenderer(policy: policy)),
            robots: RobotsCache(fetcher: URLSessionRobotsFetcher(policy: policy), policy: policy),
            resolver: SystemHostResolver(), policy: policy, limiter: HostRateLimiter(clock: ContinuousClock()))
        // TD-075: the day budget does not yet include Code-task tokens; research counts only its own spend.
        let deps = ResearchDependencies(
            safari: safari, crawler: crawler, runner: runner, store: ResearchStore(root: root),
            now: { Date() }, dayTokensUsed: { 0 })
        let pipeline = ResearchPipeline(deps: deps, settings: ResearchSettings(snapshot: snapshot))
        let inbox = ResearchInbox(folder: root)
        let viewModel = ResearchViewModel(updates: pipeline.updates, controller: pipeline, inbox: inbox, hostPolicy: policy)
        viewModel.start()
        return ResearchServices(
            viewModel: viewModel, composer: ResearchComposerViewModel(safari: safari, research: viewModel),
            pipeline: pipeline, inbox: inbox, capture: InboxCapture(safari: safari, inbox: inbox))
    }
}
