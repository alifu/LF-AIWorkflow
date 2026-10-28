//
//  ResearchPipeline.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated protocol ResearchCrawling: Sendable {
    func crawl(start: [URL], limits: CrawlLimits) -> AsyncThrowingStream<CrawlEvent, Error>
}

extension Crawler: ResearchCrawling {}

nonisolated struct ResearchDependencies: Sendable {
    let safari: any SafariControlling
    let crawler: any ResearchCrawling
    let runner: any ResearchClaudeRunning
    let store: ResearchStore
    let now: @Sendable () -> Date
    /// Tokens already spent today across all tasks (for the day budget).
    let dayTokensUsed: @Sendable () async -> Int
}

nonisolated struct ResearchSettings: Sendable {
    var taskBudget = 200_000
    var dayBudget = 2_000_000
    /// Largest corpus (tokens) sent to the analyze call directly.
    var analyzeBudget = 30_000
    /// Each source is pre-capped to this many tokens before extraction.
    var perSourceCap = 12_000
    var extractConcurrency = 2
    var policy = ResearchPolicy.defaults()

    init(taskBudget: Int = 200_000, dayBudget: Int = 2_000_000, analyzeBudget: Int = 30_000,
         perSourceCap: Int = 12_000, extractConcurrency: Int = 2, policy: ResearchPolicy = .defaults()) {
        self.taskBudget = taskBudget; self.dayBudget = dayBudget; self.analyzeBudget = analyzeBudget
        self.perSourceCap = perSourceCap; self.extractConcurrency = max(1, extractConcurrency); self.policy = policy
    }

    init(snapshot: SettingsSnapshot, policy: ResearchPolicy = .defaults()) {
        self.init(taskBudget: snapshot.taskBudget, dayBudget: snapshot.dayBudget, policy: policy)
    }
}

nonisolated enum ResearchPipelineError: Error, Equatable {
    case noPages, noSelection, noResult, noSession, illegalTransition
    case capture(String)
    case claude(String)

    var message: String {
        switch self {
        case .noPages: "No pages could be captured."
        case .noSelection: "No sources selected."
        case .noResult: "Claude returned no result."
        case .noSession: "No saved session to resume."
        case .illegalTransition: "Illegal state change."
        case .capture(let m): "Capture failed: \(m)"
        case .claude(let m): "Claude failed: \(m)"
        }
    }
}

/// Drives a research task: capture, clean, stop at the preview, then extract/analyze/report.
/// Nothing reaches Claude before `send`. Page content is untrusted and only ever travels inside nonce-tagged blocks.
actor ResearchPipeline {
    private struct Work {
        var pages: [CapturedPage]
        var saved: [SavedSource]
        var folder: ResearchFolder
        var systemPrompt = ""
        var reportBody = ""
    }

    nonisolated let updates: AsyncStream<ResearchTask>
    private let continuation: AsyncStream<ResearchTask>.Continuation
    private let deps: ResearchDependencies
    private var settings: ResearchSettings
    private var tasks: [UUID: ResearchTask] = [:]
    private var works: [UUID: Work] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]

    init(deps: ResearchDependencies, settings: ResearchSettings) {
        self.deps = deps
        self.settings = settings
        (updates, continuation) = AsyncStream.makeStream(of: ResearchTask.self)
    }

    func task(_ id: UUID) -> ResearchTask? { tasks[id] }

    func updateSettings(_ new: ResearchSettings) { settings = new }

    /// Queues a task and runs capture + clean in the background; it stops at `awaitingPreview`.
    /// Complexity: O(1) time to enqueue, O(1) space
    func submit(_ draft: ResearchDraft) -> UUID {
        let task = ResearchTask(question: draft.question, output: draft.output, deep: draft.deep)
        tasks[task.id] = task
        continuation.yield(task)
        launch(task.id) { try await $0.prepare(task.id, draft) }
        return task.id
    }

    /// Sends the non-excluded sources (1-based preview numbers) to Claude. Ignored unless the task awaits the user.
    /// Complexity: O(1) time to enqueue, O(1) space
    func send(_ id: UUID, excluded: Set<Int>) {
        guard let state = tasks[id]?.state, state == .awaitingPreview || state == .awaitingInput,
              works[id] != nil, jobs[id] == nil else { return }
        launch(id) { pipeline in
            if state == .awaitingInput { try pipeline.advance(id, .retry) { $0.with(inputReason: nil) } }
            try await pipeline.analyzeSelected(id, excluded: excluded)
        }
    }

    /// Resumes the saved session with only the question.
    func followUp(_ id: UUID, question: String) {
        guard tasks[id]?.state == .done, works[id] != nil, jobs[id] == nil else { return }
        launch(id) { try await $0.runFollowUp(id, question: question) }
    }

    /// Cancels the running job (its Claude child and crawl stop with it).
    func cancel(_ id: UUID) {
        jobs[id]?.cancel()
        _ = try? advance(id, .cancel)
    }

    // MARK: - Job plumbing

    private func launch(_ id: UUID, _ body: @escaping @Sendable (isolated ResearchPipeline) async throws -> Void) {
        jobs[id] = Task {
            do { try await body(self) } catch is CancellationError {
                _ = try? self.advance(id, .cancel)
            } catch let error as ResearchPipelineError {
                self.failTask(id, error.message)
            } catch {
                self.failTask(id, String(describing: error))
            }
            self.jobs[id] = nil
        }
    }

    private func failTask(_ id: UUID, _ message: String) {
        _ = try? advance(id, .fail) { $0.with(errorMessage: message) }
    }

    private func advance(_ id: UUID, _ event: ResearchEvent,
                         _ change: (ResearchTask) -> ResearchTask = { $0 }) throws {
        guard let current = tasks[id] else { throw ResearchPipelineError.illegalTransition }
        if current.state == .cancelled { throw CancellationError() }
        guard let next = ResearchTransitions.next(current.state, event) else { throw ResearchPipelineError.illegalTransition }
        let updated = change(current).with(state: next)
        tasks[id] = updated
        continuation.yield(updated)
    }

    private func update(_ id: UUID, _ change: (ResearchTask) -> ResearchTask) {
        guard let current = tasks[id] else { return }
        let updated = change(current)
        tasks[id] = updated
        continuation.yield(updated)
    }

    // MARK: - Capture + clean

    private func prepare(_ id: UUID, _ draft: ResearchDraft) async throws {
        try advance(id, .begin)
        let pages = try await capture(draft)
        try Task.checkCancellation()
        try advance(id, .captured)
        let removal = try TextCleaner.removeBoilerplate(pages.map(\.text))
        let duplicates = TextCleaner.duplicates(removal.pages)
        let cleaned = zip(pages, removal.pages).map { $1 == $0.text ? $0 : $0.replacingText($1) }
        let folder = try await deps.store.createFolder(question: draft.question, date: deps.now())
        var saved: [SavedSource] = []
        for (i, page) in cleaned.enumerated() {
            saved.append(try await PageCapture.save(page, index: i + 1, store: deps.store, folder: folder))
        }
        let preview = SourcesPreview.make(original: pages, cleaned: cleaned, removedLines: removal.removedLines,
                                          duplicates: duplicates)
        works[id] = Work(pages: cleaned, saved: saved, folder: folder)
        try advance(id, .cleaned) { $0.with(folder: folder).with(preview: preview) }
    }

    private func capture(_ draft: ResearchDraft) async throws -> [CapturedPage] {
        var pages: [CapturedPage] = []
        for tab in draft.tabs {
            do { pages.append(try await deps.safari.extract(tab)) } catch {
                throw ResearchPipelineError.capture("Safari \(error)")
            }
        }
        pages.append(contentsOf: draft.inboxPages)
        if !draft.urls.isEmpty {
            for try await event in deps.crawler.crawl(start: draft.urls, limits: draft.limits.clamped()) {
                if case .fetched(let page, _) = event { pages.append(page) }
            }
        }
        guard !pages.isEmpty else { throw ResearchPipelineError.noPages }
        return pages
    }

    // MARK: - Extract + analyze

    private func analyzeSelected(_ id: UUID, excluded: Set<Int>) async throws {
        guard let work = works[id], let task = tasks[id] else { throw ResearchPipelineError.illegalTransition }
        let kept = work.pages.indices.filter { !excluded.contains($0 + 1) }
        guard !kept.isEmpty else { throw ResearchPipelineError.noSelection }
        let corpus = kept.reduce(0) { $0 + work.saved[$1].tokens }
        let needsExtract = corpus > settings.analyzeBudget
        let estimate = needsExtract
            ? kept.reduce(0) { $0 + min(work.saved[$1].tokens, settings.perSourceCap) } + settings.analyzeBudget
            : corpus
        let day = await deps.dayTokensUsed()
        if task.tokensUsed + estimate > settings.taskBudget || day + estimate > settings.dayBudget {
            try advance(id, .needInput) { $0.with(inputReason: .budgetExceeded) }
            return
        }
        var texts = kept.map { work.pages[$0].text }
        if needsExtract {
            try advance(id, .startExtract)
            let extracted = try await extractAll(id, texts: texts, pages: kept.map { work.pages[$0] }, work: work)
            texts = Self.select(extracted, query: task.question, budget: settings.analyzeBudget)
            try advance(id, .extracted)
        } else {
            try advance(id, .startAnalyze)
        }
        let survivors = zip(kept, texts).filter { !$0.1.isEmpty }.map { (page: work.pages[$0.0], text: $0.1) }
        guard !survivors.isEmpty else { throw ResearchPipelineError.noSelection }
        try await analyze(id, survivors: survivors, work: work)
    }

    private func analyze(_ id: UUID, survivors: [(page: CapturedPage, text: String)], work: Work) async throws {
        guard let task = tasks[id] else { throw ResearchPipelineError.illegalTransition }
        let sources = survivors.enumerated().map { PromptSource(id: $0 + 1, url: $1.page.url, text: $1.text) }
        let tables = promptTables(survivors.map(\.page), sources: sources)
        let nonce = ResearchPromptBuilder.makeNonce(
            avoiding: sources.map(\.text) + tables.map(\.csv) + [task.question])
        let system = ResearchPromptBuilder.systemPrompt(nonce: nonce)
        let prompt = ResearchPromptBuilder.analyzePrompt(
            question: task.question, sources: sources, tables: tables, output: task.output, nonce: nonce)
        let request = ResearchRunRequest(
            stage: .analyze, config: settings.policy.config(for: .analyze, deep: task.deep, systemPrompt: system),
            prompt: prompt, sessionId: nil, workingDirectory: work.folder.url)
        let outcome = try await Self.collect(deps.runner, request)
        record(id, outcome)
        try advance(id, .analyzed)
        let report = ReportWriter.parse(outcome.text ?? "", sourceCount: sources.count)
        let resources = survivors.map { ResearchSource(url: $0.page.url.absoluteString, title: $0.page.title, body: "") }
        let markdown = ReportWriter.render(report, sources: resources)
        let file = try await deps.store.writeReport(markdown, in: work.folder)
        if let table = report.table { _ = try await deps.store.writeComparisonCSV(table.csvRows, in: work.folder) }
        works[id]?.systemPrompt = system
        works[id]?.reportBody = markdown
        try advance(id, .reported) { $0.with(reportFile: file) }
    }

    private func runFollowUp(_ id: UUID, question: String) async throws {
        guard let work = works[id], let task = tasks[id] else { throw ResearchPipelineError.illegalTransition }
        guard let session = task.sessionId else { throw ResearchPipelineError.noSession }
        try advance(id, .followUp)
        let request = ResearchRunRequest(
            stage: .followUp,
            config: settings.policy.config(for: .followUp, deep: task.deep, systemPrompt: work.systemPrompt),
            prompt: ResearchPromptBuilder.followUpPrompt(question: question), sessionId: session,
            workingDirectory: work.folder.url)
        let outcome = try await Self.collect(deps.runner, request)
        record(id, outcome)
        try advance(id, .analyzed)
        let answer = ReportWriter.parse(outcome.text ?? "", sourceCount: Int.max / 2).answer
        let heading = ReportWriter.sanitize(question).replacingOccurrences(of: "\n", with: " ")
        let markdown = work.reportBody + "\n\n## Follow-up: \(heading)\n\n\(answer)\n"
        let file = try await deps.store.writeReport(markdown, in: work.folder)
        works[id]?.reportBody = markdown
        try advance(id, .reported) { $0.with(reportFile: file) }
    }

    private func extractAll(_ id: UUID, texts: [String], pages: [CapturedPage], work: Work) async throws -> [String] {
        let cap = settings.perSourceCap
        let runner = deps.runner
        let policy = settings.policy
        let folder = work.folder.url
        var results = [String](repeating: "", count: texts.count)
        var usage: [StageRunOutcome] = []
        try await withThrowingTaskGroup(of: (Int, StageRunOutcome).self) { group in
            var next = 0
            func enqueue() {
                guard next < texts.count else { return }
                let i = next
                next += 1
                let text = Self.capped(texts[i], tokens: cap)
                let nonce = ResearchPromptBuilder.makeNonce(avoiding: [text])
                let prompt = ResearchPromptBuilder.extractPrompt(
                    source: PromptSource(id: i + 1, url: pages[i].url, text: text), nonce: nonce)
                let request = ResearchRunRequest(
                    stage: .extract,
                    config: policy.config(for: .extract, deep: false, systemPrompt: ResearchPromptBuilder.systemPrompt(nonce: nonce)),
                    prompt: prompt, sessionId: nil, workingDirectory: folder)
                group.addTask { (i, try await Self.collect(runner, request)) }
            }
            for _ in 0..<settings.extractConcurrency { enqueue() }
            while let (i, outcome) = try await group.next() {
                results[i] = outcome.text ?? ""
                usage.append(outcome)
                enqueue()
            }
        }
        for outcome in usage { record(id, outcome) }
        return results
    }

    private func promptTables(_ pages: [CapturedPage], sources: [PromptSource]) -> [PromptTable] {
        var remaining = settings.analyzeBudget - sources.reduce(0) { $0 + TokenEstimator.estimate($1.text) }
        var out: [PromptTable] = []
        for (i, page) in pages.enumerated() {
            for (k, rows) in page.tables.enumerated() {
                let csv = CSVWriter.document(rows)
                let cost = TokenEstimator.estimate(csv)
                guard cost <= remaining else { continue }
                remaining -= cost
                out.append(PromptTable(sourceId: i + 1, name: "\(i + 1)-\(k + 1)", csv: csv))
            }
        }
        return out
    }

    private func record(_ id: UUID, _ outcome: StageRunOutcome) {
        update(id) {
            $0.with(tokensUsed: $0.tokensUsed + outcome.usage.billableTotal)
                .with(sessionId: outcome.sessionId ?? $0.sessionId)
                .with(denials: $0.denials + outcome.permissionDenials)
        }
    }

    // MARK: - Pure helpers

    /// Runs one research call and returns its final outcome; an error result throws.
    /// Complexity: O(e) time over the stream's events, O(1) space
    nonisolated private static func collect(_ runner: any ResearchClaudeRunning,
                                            _ request: ResearchRunRequest) async throws -> StageRunOutcome {
        var final: StageRunOutcome?
        for try await event in runner.run(request) {
            if case .finished(let outcome) = event { final = outcome }
        }
        try Task.checkCancellation()
        guard let outcome = final else { throw ResearchPipelineError.noResult }
        if outcome.isError { throw ResearchPipelineError.claude(outcome.text ?? "unknown error") }
        return outcome
    }

    /// Shrinks `text` until its estimated tokens fit `tokens`.
    /// Complexity: O(n) time per pass, bounded passes, O(n) space
    nonisolated static func capped(_ text: String, tokens: Int) -> String {
        var current = text
        for _ in 0..<8 {
            let estimate = TokenEstimator.estimate(current)
            if estimate <= tokens { break }
            current = String(current.prefix(max(1, current.count * tokens / estimate)))
        }
        return current
    }

    /// Picks the chunks of the extracted facts that best match the question, within `budget` tokens.
    /// Returns one text per input source (empty when nothing was selected from it).
    /// Complexity: O(total bytes + c log c) time for c chunks, O(c) space
    nonisolated static func select(_ extracted: [String], query: String, budget: Int) -> [String] {
        var chunks: [(source: Int, text: String)] = []
        for (s, text) in extracted.enumerated() {
            chunks.append(contentsOf: Chunker.chunks(text).map { (s, $0) })
        }
        let ranked = ((try? BM25.topK(chunks: chunks.map(\.text), query: query, k: chunks.count)) ?? []).map(\.index)
        let order = ranked.isEmpty ? Array(chunks.indices) : ranked
        var chosen = Set<Int>()
        var used = 0
        for i in order {
            let cost = TokenEstimator.estimate(chunks[i].text)
            guard used + cost <= budget else { continue }
            used += cost
            chosen.insert(i)
        }
        var out = [String](repeating: "", count: extracted.count)
        for i in chosen.sorted() {
            let s = chunks[i].source
            out[s] += (out[s].isEmpty ? "" : "\n\n") + chunks[i].text
        }
        return out
    }
}

nonisolated extension CapturedPage {
    /// Copy with different text (used after boilerplate removal).
    func replacingText(_ newText: String) -> CapturedPage {
        CapturedPage(title: title, url: url, text: newText, headings: headings, links: links, tables: tables,
                     hasPasswordField: hasPasswordField)
    }
}
