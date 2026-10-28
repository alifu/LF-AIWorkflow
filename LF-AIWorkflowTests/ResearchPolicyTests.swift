//
//  ResearchPolicyTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
@testable import LF_AIWorkflow

struct ResearchPolicyTests {
    private let policy = ResearchPolicy.defaults()

    @Test(arguments: ResearchStage.allCases, [false, true])
    func invariants(stage: ResearchStage, deep: Bool) {
        let c = policy.config(for: stage, deep: deep, systemPrompt: "p")
        #expect(Set(c.builtinTools ?? ["?"]).isSubset(of: ["Read"]))
        for t in ResearchPolicy.deniedTools + StagePolicy.alwaysDenied { #expect(c.disallowedTools.contains(t)) }
        for rule in c.allowedTools {
            #expect(!rule.hasPrefix("Bash") && !rule.hasPrefix("Write") && !rule.hasPrefix("Web"))
        }
        #expect(c.isolated)
        #expect(c.permissionMode == .default)
    }

    @Test func extractHasNoTools() {
        let c = policy.config(for: .extract, deep: true, systemPrompt: "p")
        #expect(c.builtinTools == [] && c.allowedTools.isEmpty && c.maxTurns == 1 && c.model == "haiku")
    }

    @Test func analyzeModelsAndTurns() {
        #expect(policy.config(for: .analyze, deep: false, systemPrompt: "p").model == "sonnet")
        #expect(policy.config(for: .analyze, deep: true, systemPrompt: "p").model == "opus")
        #expect(policy.config(for: .analyze, deep: false, systemPrompt: "p").maxTurns == 6)
        #expect(policy.config(for: .followUp, deep: false, systemPrompt: "p").maxTurns == 4)
    }

    @Test func overridesChangeModelsOnly() {
        let o = policy.overriding(models: [.extract: "sonnet"])
        let c = o.config(for: .extract, deep: false, systemPrompt: "p")
        #expect(c.model == "sonnet" && c.builtinTools == [] && c.isolated)
    }

    @Test func argvFlags() throws {
        let e = try ClaudeCommandBuilder.arguments(config: policy.config(for: .extract, deep: false, systemPrompt: "sys"),
                                                   sessionId: nil, addDirs: [])
        let i = try #require(e.firstIndex(of: "--tools"))
        #expect(e[i + 1] == "")
        #expect(e.contains("--strict-mcp-config") && e.contains("--disable-slash-commands"))
        #expect(e.contains("--append-system-prompt"))
        let a = try ClaudeCommandBuilder.arguments(config: policy.config(for: .analyze, deep: false, systemPrompt: "sys"),
                                                   sessionId: nil, addDirs: [])
        let j = try #require(a.firstIndex(of: "--tools"))
        #expect(a[j + 1] == "Read")
    }

    @Test func builderValidation() {
        func cfg(tools: [String]? = nil, prompt: String? = nil) -> StageConfig {
            StageConfig(model: "haiku", escalationModel: nil, permissionMode: .default, allowedTools: [],
                        disallowedTools: [], maxTurns: 1, builtinTools: tools, appendSystemPrompt: prompt)
        }
        #expect(throws: ClaudeCommandError.invalidToolName("Re ad")) {
            try ClaudeCommandBuilder.arguments(config: cfg(tools: ["Re ad"]), sessionId: nil, addDirs: [])
        }
        #expect(throws: ClaudeCommandError.invalidSystemPrompt) {
            try ClaudeCommandBuilder.arguments(config: cfg(prompt: "a\0b"), sessionId: nil, addDirs: [])
        }
        #expect(throws: ClaudeCommandError.invalidSystemPrompt) {
            try ClaudeCommandBuilder.arguments(config: cfg(prompt: String(repeating: "x", count: 8193)), sessionId: nil, addDirs: [])
        }
    }

    @Test func oldJSONDecodes() throws {
        let json = #"{"model":"haiku","permissionMode":"default","allowedTools":[],"disallowedTools":[],"maxTurns":2}"#
        let c = try JSONDecoder().decode(StageConfig.self, from: Data(json.utf8))
        #expect(c.builtinTools == nil && !c.isolated && c.appendSystemPrompt == nil)
    }
}
