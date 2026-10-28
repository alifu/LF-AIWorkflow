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
    static func makeViewModel() async -> WorkflowViewModel {
        let snapshot = settings.snapshot()
        let searchPath = await resolveSearchPath()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        let locator = ToolLocator(searchPath: searchPath, overrides: snapshot.toolPaths)
        let engineSettings = EngineSettings.from(snapshot)
        let claude: any ClaudeStageRunning
        do {
            claude = ClaudeStageRunner(executable: try locator.locate(.claude), baseEnvironment: environment, searchPath: searchPath)
        } catch {
            claude = UnavailableClaudeRunner(error: error)
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
        return model
    }
}
