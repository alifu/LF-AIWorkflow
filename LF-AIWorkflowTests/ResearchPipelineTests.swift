//
//  ResearchPipelineTests.swift
//  LF-AIWorkflowTests
//

import Foundation
import Testing
@testable import LF_AIWorkflow

struct ResearchPipelineTests {
    private struct Harness {
        let pipeline: ResearchPipeline
        let runner: FakeResearchRunner
        let root: URL
    }

    private func fixture(_ name: String) throws -> String {
        String(decoding: try loadFixture(name), as: UTF8.self)
    }

    private func page(_ n: Int, paragraphs: Int = 3, tag: String = "p") -> CapturedPage {
        let body = (0..<paragraphs).map {
            "Section \(tag)\(n) paragraph \($0) discusses product\(n) pricing and speed detail \($0 * 31 + n)."
        }.joined(separator: "\n\n")
        return CapturedPage(title: "Page \(n)", url: URL(string: "https://site\(n).example.com/a")!,
                            text: body, headings: [], links: [], tables: [[["Name", "Price"], ["P\(n)", "\(n)"]]],
                            hasPasswordField: false)
    }

    private func harness(pages: [CapturedPage], settings: ResearchSettings = ResearchSettings(), dayUsed: Int = 0,
                         handler: @escaping @Sendable (ResearchRunRequest) -> FakeResearchRunner.Reply) throws -> Harness {
        let root = try TestEnv.makeTempDir()
        let runner = FakeResearchRunner(handler: handler)
        let deps = ResearchDependencies(
            safari: FakeSafari(pages: [:]), crawler: FakeCrawler(pages: pages), runner: runner,
            store: ResearchStore(root: root), now: { Date(timeIntervalSince1970: 1_700_000_000) },
            dayTokensUsed: { dayUsed })
        return Harness(pipeline: ResearchPipeline(deps: deps, settings: settings), runner: runner, root: root)
    }

    private func draft(_ question: String = "Which is faster?", deep: Bool = false) -> ResearchDraft {
        ResearchDraft(question: question, output: .comparison, deep: deep,
                      urls: [URL(string: "https://site1.example.com/a")!])
    }

    private func wait(_ pipeline: ResearchPipeline, _ id: UUID, for state: ResearchState) async throws -> ResearchTask {
        for _ in 0..<1000 {
            if let t = await pipeline.task(id), t.state == state { return t }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for \(state)")
        throw CancellationError()
    }

    private func answer() throws -> FakeResearchRunner.Reply { FakeResearchRunner.ok(try fixture("answer-good.md")) }

    // MARK: -

    @Test func previewIsReachedWithoutAnyClaudeCall() async throws {
        let h = try harness(pages: [page(1), page(2)]) { _ in FakeResearchRunner.ok("never") }
        let id = await h.pipeline.submit(draft())
        let task = try await wait(h.pipeline, id, for: .awaitingPreview)
        #expect(h.runner.calls.isEmpty)
        let preview = try #require(task.preview)
        #expect(preview.rows.count == 2)
        #expect(preview.rows[0].host == "site1.example.com")
        #expect(preview.rows[0].tables == 1)
        #expect(preview.totalTokens == preview.rows.map(\.tokens).reduce(0, +))
        #expect(task.folder != nil)
    }

    @Test func identicalAndEmptyPagesAreFlagged() async throws {
        let dup = page(1, paragraphs: 1)
        let h = try harness(pages: [dup, dup]) { _ in FakeResearchRunner.ok("never") }
        let id = await h.pipeline.submit(draft())
        let preview = try #require(try await wait(h.pipeline, id, for: .awaitingPreview).preview)
        #expect(preview.rows[1].flags.contains(.duplicate))
        #expect(!preview.rows[0].flags.contains(.duplicate))
        #expect(preview.rows[0].flags.contains(.looksEmpty))
    }

    @Test func excludedSourcesAreAbsentFromThePrompt() async throws {
        let reply = try answer()
        let h = try harness(pages: [page(1), page(2), page(3)]) { _ in reply }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [2])
        let done = try await wait(h.pipeline, id, for: .done)
        let prompt = try #require(h.runner.calls.first).prompt
        #expect(prompt.contains("site1.example.com"))
        #expect(!prompt.contains("site2.example.com"))
        #expect(prompt.contains("site3.example.com"))
        let report = try String(contentsOf: #require(done.reportFile), encoding: .utf8)
        #expect(!report.contains("site2.example.com"))
        #expect(report.contains("## Sources"))
    }

    @Test func smallCorpusSkipsExtractAndUsesResearchFolderOnly() async throws {
        let reply = try answer()
        let h = try harness(pages: [page(1), page(2)]) { _ in reply }
        let id = await h.pipeline.submit(draft())
        let preview = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        let done = try await wait(h.pipeline, id, for: .done)
        let calls = h.runner.calls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.stage == .analyze)
        #expect(call.workingDirectory == preview.folder?.url)
        #expect(call.config == ResearchPolicy.defaults().config(
            for: .analyze, deep: false, systemPrompt: try #require(call.config.appendSystemPrompt)))
        #expect(call.config.isolated)
        #expect(call.sessionId == nil)
        #expect(call.prompt.hasSuffix("Which is faster?"))
        #expect(done.sessionId == "22222222-2222-4222-8222-222222222222")
        #expect(done.tokensUsed == 100)
        #expect(FileManager.default.fileExists(atPath: try #require(done.reportFile).path))
    }

    @Test func deepFlagSelectsOpus() async throws {
        let reply = try answer()
        let h = try harness(pages: [page(1)]) { _ in reply }
        let id = await h.pipeline.submit(draft(deep: true))
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .done)
        #expect(h.runner.calls.first?.config.model == "opus")
    }

    @Test func largeCorpusExtractsPerSourceThenSelectsWithinBudget() async throws {
        let big = (1...3).map { page($0, paragraphs: 400, tag: "big") }
        let recorded = try fixture("pipeline-extract-recorded.md")
        let longFacts = (0..<600).map { "Fact \($0) about speed and pricing of the product, number \($0 * 17)." }
            .joined(separator: "\n\n")
        let settings = ResearchSettings(analyzeBudget: 3_000, perSourceCap: 2_000)
        let reply = try answer()
        let h = try harness(pages: big, settings: settings) { req in
            switch req.stage {
            case .extract: return FakeResearchRunner.ok(recorded + "\n\n" + longFacts, tokens: 10)
            default: return reply
            }
        }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .done)
        let calls = h.runner.calls
        let extracts = calls.filter { $0.stage == .extract }
        #expect(extracts.count == 3)
        for e in extracts {
            #expect(e.config.builtinTools == [])
            #expect(e.config.model == "haiku")
            #expect(TokenEstimator.estimate(e.prompt) <= 2_000 + 400)
        }
        let analyze = try #require(calls.last)
        #expect(analyze.stage == .analyze)
        #expect(TokenEstimator.estimate(analyze.prompt) <= 3_000 + 600)
    }

    @Test func followUpResumesSessionWithOnlyTheQuestion() async throws {
        let reply = try answer()
        let h = try harness(pages: [page(1)]) { req in
            req.stage == .followUp ? FakeResearchRunner.ok("Beta wins on price [1].", tokens: 5) : reply
        }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .done)
        await h.pipeline.followUp(id, question: "And on price?")
        let done = try await wait(h.pipeline, id, for: .done)
        let call = try #require(h.runner.calls.last)
        #expect(call.stage == .followUp)
        #expect(call.sessionId == "22222222-2222-4222-8222-222222222222")
        #expect(call.prompt == "And on price?")
        #expect(done.tokensUsed == 105)
        let report = try String(contentsOf: #require(done.reportFile), encoding: .utf8)
        #expect(report.contains("Beta wins on price"))
        #expect(report.contains("Alpha is faster"))
    }

    @Test func claudeErrorFailsTheTaskWithItsMessage() async throws {
        let h = try harness(pages: [page(1)]) { _ in FakeResearchRunner.error("rate limited") }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        let failed = try await wait(h.pipeline, id, for: .failed)
        #expect(failed.errorMessage?.contains("rate limited") == true)
    }

    @Test func overTaskBudgetWaitsForInputWithoutCallingClaude() async throws {
        let h = try harness(pages: [page(1)], settings: ResearchSettings(taskBudget: 1)) { _ in FakeResearchRunner.ok("never") }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        let waiting = try await wait(h.pipeline, id, for: .awaitingInput)
        #expect(waiting.inputReason == .budgetExceeded)
        #expect(h.runner.calls.isEmpty)
    }

    @Test func overDayBudgetWaitsForInput() async throws {
        let h = try harness(pages: [page(1)], settings: ResearchSettings(dayBudget: 100), dayUsed: 100) { _ in
            FakeResearchRunner.ok("never")
        }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .awaitingInput)
        #expect(h.runner.calls.isEmpty)
    }

    @Test func raisingTheBudgetLetsTheTaskContinue() async throws {
        let reply = try answer()
        let h = try harness(pages: [page(1)], settings: ResearchSettings(taskBudget: 1)) { _ in reply }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .awaitingInput)
        await h.pipeline.updateSettings(ResearchSettings())
        await h.pipeline.send(id, excluded: [])
        _ = try await wait(h.pipeline, id, for: .done)
    }

    @Test func permissionDenialsAreRecordedOnTheTask() async throws {
        let text = try fixture("answer-good.md")
        let h = try harness(pages: [page(1)]) { _ in FakeResearchRunner.ok(text, denials: ["Bash"]) }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        let done = try await wait(h.pipeline, id, for: .done)
        #expect(done.denials == ["Bash"])
    }

    @Test func cancelStopsTheChildAndMarksCancelled() async throws {
        let h = try harness(pages: [page(1)]) { _ in .hang }
        let id = await h.pipeline.submit(draft())
        _ = try await wait(h.pipeline, id, for: .awaitingPreview)
        await h.pipeline.send(id, excluded: [])
        for _ in 0..<400 where h.runner.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await h.pipeline.cancel(id)
        _ = try await wait(h.pipeline, id, for: .cancelled)
        for _ in 0..<400 where h.runner.terminatedCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(h.runner.terminatedCount == 1)
    }

    @Test func emptyCaptureFailsTheTask() async throws {
        let h = try harness(pages: []) { _ in FakeResearchRunner.ok("never") }
        let id = await h.pipeline.submit(draft())
        let failed = try await wait(h.pipeline, id, for: .failed)
        #expect(failed.errorMessage != nil)
    }

    @Test func safariTabsAreCapturedThroughTheBridge() async throws {
        let tabURL = URL(string: "https://site7.example.com/a")!
        let root = try TestEnv.makeTempDir()
        let runner = FakeResearchRunner { _ in FakeResearchRunner.ok("never") }
        let deps = ResearchDependencies(
            safari: FakeSafari(pages: [tabURL: page(7)]), crawler: FakeCrawler(pages: []), runner: runner,
            store: ResearchStore(root: root), now: { Date() }, dayTokensUsed: { 0 })
        let pipeline = ResearchPipeline(deps: deps, settings: ResearchSettings())
        let tab = SafariTab(window: 1, tab: 1, title: "t", url: tabURL, current: true)
        let id = await pipeline.submit(ResearchDraft(question: "q", output: .summary, deep: false, tabs: [tab]))
        let task = try await wait(pipeline, id, for: .awaitingPreview)
        #expect(task.preview?.rows.first?.host == "site7.example.com")
    }

    @Test func updatesStreamPublishesEveryStateInOrder() async throws {
        let h = try harness(pages: [page(1)]) { _ in FakeResearchRunner.ok("never") }
        let id = await h.pipeline.submit(draft())
        var seen: [ResearchState] = []
        for await t in h.pipeline.updates where t.id == id {
            if seen.last != t.state { seen.append(t.state) }
            if t.state == .awaitingPreview { break }
        }
        #expect(seen == [.queued, .capture, .clean, .awaitingPreview])
    }
}
