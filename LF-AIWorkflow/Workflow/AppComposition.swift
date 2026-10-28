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
    /// Resolves the login-shell PATH off the main actor, locates the tools and wires the engine.
    /// Complexity: O(d) time over PATH entries plus the login-shell run (bounded by its 5 s timeout), O(d) space
    static func makeViewModel() async -> WorkflowViewModel {
        let loginPath = await LoginShellPath().resolve()
        let env = ProcessInfo.processInfo.environment
        let searchPath = ToolLocator.searchPath(loginShellPATH: loginPath, processPATH: env["PATH"], home: NSHomeDirectory())
        var environment = env
        environment["PATH"] = searchPath.joined(separator: ":")
        let locator = ToolLocator(searchPath: searchPath)
        let settings = EngineSettings.default
        let claude: any ClaudeStageRunning
        do {
            claude = ClaudeStageRunner(executable: try locator.locate(.claude), baseEnvironment: environment, searchPath: searchPath)
        } catch {
            claude = UnavailableClaudeRunner(error: error)
        }
        let git = GitClient(locator: locator, environment: environment)
        let logs = TaskLogStore()
        let deps = EngineDependencies(
            claude: claude, tests: TestRunner(override: settings.testCommandOverride, environment: environment),
            graph: GraphifyClient(locator: locator, environment: environment), git: git,
            worktrees: WorktreeManager(git: git), log: logs)
        let engine = WorkflowEngine(dependencies: deps, settings: settings)
        let model = WorkflowViewModel(engine: engine, logs: logs, fixLoopCap: settings.fixLoopCap)
        model.start()
        return model
    }
}
