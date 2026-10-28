//
//  StagePolicyTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

struct StagePolicyTests {
    private let policy = StagePolicy.defaults(testCommand: "xcodebuild test")

    @Test(arguments: WorkflowStage.allCases)
    func everyStageDeniesAlwaysDeniedTools(stage: WorkflowStage) {
        let config = policy.config(for: stage)
        #expect(Set(StagePolicy.alwaysDenied).isSubset(of: Set(config.disallowedTools)))
        #expect(Set(config.disallowedTools).count == config.disallowedTools.count)
    }

    @Test func tableMatchesPlan() {
        let plan = policy.config(for: .plan)
        #expect(plan.model == "opus" && plan.permissionMode == .plan && plan.maxTurns == 8)
        #expect(plan.allowedTools == ["Read", "Grep", "Glob", "Bash(graphify:*)"])
        let code = policy.config(for: .code)
        #expect(code.model == "sonnet" && code.permissionMode == .acceptEdits && code.maxTurns == 20)
        #expect(code.allowedTools == ["Read", "Write", "Edit", "Grep", "Glob", "Bash(graphify:*)", "Bash(xcodebuild test)"])
        let fix = policy.config(for: .fix)
        #expect(fix.model == "haiku" && fix.escalationModel == "sonnet")
        #expect(fix.permissionMode == .acceptEdits && fix.maxTurns == 10)
        #expect(fix.allowedTools == code.allowedTools)
        let review = policy.config(for: .review)
        #expect(review.model == "opus" && review.permissionMode == .default && review.maxTurns == 8)
        #expect(review.allowedTools == ["Read", "Grep", "Glob", "Bash(git diff:*)"])
        #expect(code.escalationModel == nil)
    }

    @Test func reviewNeverAllowsWriteToolsEvenAfterReplacing() {
        let sneaky = StageConfig(model: "opus", escalationModel: nil, permissionMode: .acceptEdits,
                                 allowedTools: ["Read", "Write", "Edit", "NotebookEdit"], disallowedTools: [], maxTurns: 5)
        let config = policy.replacing(.review, with: sneaky).config(for: .review)
        #expect(Set(config.allowedTools).isDisjoint(with: StagePolicy.writeTools))
        #expect(config.allowedTools == ["Read"])
        #expect(Set(StagePolicy.writeTools).isSubset(of: Set(config.disallowedTools)))
        #expect(Set(StagePolicy.alwaysDenied).isSubset(of: Set(config.disallowedTools)))
    }

    @Test func nilOrEmptyTestCommandAddsNoBashEntry() {
        for command in [nil, ""] as [String?] {
            let code = StagePolicy.defaults(testCommand: command).config(for: .code)
            #expect(code.allowedTools == ["Read", "Write", "Edit", "Grep", "Glob", "Bash(graphify:*)"])
        }
    }

    @Test func testCommandBecomesBashEntry() {
        let code = StagePolicy.defaults(testCommand: "scripts/check.sh").config(for: .code)
        #expect(code.allowedTools.contains("Bash(scripts/check.sh)"))
    }

    @Test func replacingLeavesOriginalUnchanged() {
        let original = StagePolicy.defaults(testCommand: nil)
        let custom = StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default,
                                 allowedTools: ["Read"], disallowedTools: ["Bash(curl:*)"], maxTurns: 3)
        let changed = original.replacing(.code, with: custom)
        #expect(original == StagePolicy.defaults(testCommand: nil))
        #expect(changed != original)
        let config = changed.config(for: .code)
        #expect(config.model == "haiku" && config.maxTurns == 3)
        #expect(config.disallowedTools == ["Bash(curl:*)"] + StagePolicy.alwaysDenied)
    }

    @Test func reviewDeniesGitDiffOutputFileAndAbbreviations() {
        let denied = StagePolicy.defaults(testCommand: nil).config(for: .review).disallowedTools
        #expect(denied.contains("Bash(git diff *--out*)"))
        #expect(!denied.contains("Bash(git diff --output:*)"))
        #expect(!denied.contains("Bash(git diff * --output:*)"))
    }
}
