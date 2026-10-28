//
//  PreviewFixtures.swift
//  LF-AIWorkflow
//

#if DEBUG
import Foundation

/// Fixture tasks for `#Preview`s and unit tests (debug builds only).
nonisolated enum PreviewFixtures {
    static let project = URL(fileURLWithPath: "/tmp/MyApp", isDirectory: true)
    static let epoch = Date(timeIntervalSince1970: 1_000)

    static func task(_ title: String = "Login biometric", state: TaskState = .code, id: UUID = UUID(),
                     created: Date = epoch, fixAttempts: Int = 0, tokens: Int = 0, planFile: URL? = nil,
                     reviewFile: URL? = nil, worktree: Bool = false, wait: WaitReason? = nil,
                     resume: TaskState? = nil, failure: FailureReason? = nil) -> WorkflowTask {
        let usage = tokens > 0 ? [WorkflowStage.code: TokenUsage(input: tokens, output: 0, cacheRead: 0, cacheCreation: 0)] : [:]
        let tree = worktree ? Worktree(path: project.appendingPathComponent(".wt/\(title)"), branch: "lf/\(title)", baseCommit: "abc") : nil
        return WorkflowTask(
            id: id, title: title, slug: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            prompt: "Do the thing", projectRoot: project, documents: [], skillDirs: [], state: state,
            resumeState: resume, waitReason: wait, failure: failure, worktree: tree, sessionId: nil,
            planFile: planFile, fixAttempts: fixAttempts, usageByStage: usage, lastErrors: nil,
            testCommandDisplay: nil, reviewFile: reviewFile, createdAt: created)
    }

    static var sampleTasks: [WorkflowTask] {
        let plan = project.appendingPathComponent(".claude/plans/login.md")
        return [
            task("Add dark mode", state: .awaitingApproval, planFile: plan),
            task("Fix crash on rotate", state: .fix, fixAttempts: 1, tokens: 12_400, worktree: true),
            task("Refactor networking", state: .code, tokens: 2_200),
            task("Update README", state: .done, planFile: plan),
        ]
    }
}
#endif

#if DEBUG
extension PreviewFixtures {
    struct SamplePlanLoader: PlanLoading {
        func load(_ url: URL) async throws -> PlanDocument {
            PlanDocument(path: url, steps: ["Add the theme model", "Wire the settings toggle", "Write tests"],
                         estimatedTokens: 1_800, isTruncated: false)
        }
    }

    struct SampleReviewLoader: ReviewLoading {
        func load(_ url: URL) async throws -> ReviewReport {
            ReviewReport(findings: [
                Finding(severity: .high, file: "Theme.kt", line: 31, issue: "Hardcoded color", suggestion: "Use the theme token"),
                Finding(severity: .low, file: "Net.swift", line: nil, issue: "No timeout", suggestion: nil),
            ], unparsedLineCount: 0)
        }
    }

    static var planLoader: any PlanLoading { SamplePlanLoader() }
    static var reviewLoader: any ReviewLoading { SampleReviewLoader() }
}
#endif
