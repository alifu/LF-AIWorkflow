//
//  ComposerViewModel.swift
//  LF-AIWorkflow
//

import Foundation
import Observation

@MainActor @Observable
final class ComposerViewModel {
    private let bookmarks: any BookmarkStoring
    private let picker: any FilePicking
    private let inspector: any AttachmentInspecting
    private let policy: AttachmentPolicy
    private let estimator: @Sendable (String) -> Int
    private let accessHooks: ScopedAccess.Hooks

    var prompt = ""
    /// Skip Plan and approval (TD-044). Cleared after each start.
    var startAtCode = false
    /// Per-task worktree choice (TD-044).
    var useWorktree = true
    private(set) var projectRoot: URL?
    private(set) var documents: [Attachment] = []
    private(set) var skillDirs: [URL] = []
    /// Secret-looking files waiting for the user's confirmation; not yet in `documents`.
    private(set) var pendingSecrets: [Attachment] = []
    private(set) var notices: [String] = []

    init(bookmarks: any BookmarkStoring, picker: any FilePicking, inspector: any AttachmentInspecting,
         policy: AttachmentPolicy = .standard, estimator: @escaping @Sendable (String) -> Int = TokenEstimator.estimate,
         accessHooks: ScopedAccess.Hooks = .system) {
        self.bookmarks = bookmarks
        self.picker = picker
        self.inspector = inspector
        self.policy = policy
        self.estimator = estimator
        self.accessHooks = accessHooks
    }

    /// Held while the composer is on screen; keyed by standardized path.
    private var accesses: [URL: ScopedAccess] = [:]

    /// Prompt tokens plus documents small enough to inline; larger documents go in as paths only.
    /// Complexity: O(prompt + d) time, O(1) space
    var estimatedTokens: Int { estimator(prompt) + documents.reduce(0) { $0 + $1.inlineTokens } }

    var canStart: Bool {
        projectRoot != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var documentLimitText: String { "\(documents.count) of \(policy.maxDocuments) files" }

    /// Switches project and loads its remembered skill folders; folders that vanished are forgotten with a notice.
    /// Complexity: O(k) time, O(k) space
    func setProject(_ url: URL?) {
        projectRoot = url
        for dir in skillDirs { release(dir) }
        skillDirs = []
        guard let url else { return }
        let loaded = bookmarks.loadSkillFolders(project: url)
        for folder in loaded.folders { acquire(folder) }
        skillDirs = loaded.folders
        for path in loaded.dropped { notices.append("Skill folder \(path) no longer exists and was forgotten.") }
    }

    /// Attaches files; returns what was refused. Secret-looking files wait in `pendingSecrets` for confirmation.
    /// File metadata is read off the main actor; nothing is read from file contents here.
    /// Complexity: O(n) time, O(n) space (n = urls)
    @discardableResult
    func addDocuments(_ urls: [URL]) async -> [Rejected] {
        let inspected = await inspectAll(urls)
        var rejected: [Rejected] = []
        var seen = Set((documents + pendingSecrets).map(\.url))
        var slots = policy.maxDocuments - documents.count - pendingSecrets.count
        for (url, info) in inspected {
            let name = url.lastPathComponent
            let key = url.standardizedFileURL
            guard let info else { rejected.append(Rejected(name: name, reason: .notFileURL)); continue }
            guard !seen.contains(key) else { rejected.append(Rejected(name: name, reason: .duplicate)); continue }
            if let reason = documentRejection(info) { rejected.append(Rejected(name: name, reason: reason)); continue }
            guard slots > 0 else { rejected.append(Rejected(name: name, reason: .limitReached(max: policy.maxDocuments))); continue }
            seen.insert(key)
            slots -= 1
            let secret = AttachmentPolicy.isSecret(url: key)
            let attachment = Attachment(url: key, bytes: info.bytes, inlineTokens: info.inlineTokens, isSecret: secret)
            if secret { pendingSecrets.append(attachment) } else { documents.append(attachment); acquire(key) }
        }
        notices.append(contentsOf: rejected.map { $0.reason.message(for: $0.name) })
        return rejected
    }

    /// Complexity: O(n) time, O(n) space
    @discardableResult
    func addSkillFolders(_ urls: [URL]) async -> [Rejected] {
        let inspected = await inspectAll(urls)
        var rejected: [Rejected] = []
        for (url, info) in inspected {
            let name = url.lastPathComponent
            let key = url.standardizedFileURL
            guard let info else { rejected.append(Rejected(name: name, reason: .notFileURL)); continue }
            if skillDirs.contains(key) { rejected.append(Rejected(name: name, reason: .duplicate)); continue }
            switch info.kind {
            case .missing: rejected.append(Rejected(name: name, reason: .missing)); continue
            case .file: rejected.append(Rejected(name: name, reason: .notDirectory)); continue
            case .directory: break
            }
            guard info.isReadable else { rejected.append(Rejected(name: name, reason: .unreadable)); continue }
            guard skillDirs.count < policy.maxSkillFolders else {
                rejected.append(Rejected(name: name, reason: .limitReached(max: policy.maxSkillFolders))); continue
            }
            skillDirs.append(key)
            acquire(key)
        }
        persistSkillFolders()
        notices.append(contentsOf: rejected.map { $0.reason.message(for: $0.name) })
        return rejected
    }

    func removeDocument(_ url: URL) {
        let key = url.standardizedFileURL
        documents.removeAll { $0.url == key }
        release(key)
    }

    func removeSkillFolder(_ url: URL) {
        let key = url.standardizedFileURL
        skillDirs.removeAll { $0 == key }
        release(key)
        persistSkillFolders()
    }

    func confirmSecrets() {
        for secret in pendingSecrets where documents.count < policy.maxDocuments {
            documents.append(secret)
            acquire(secret.url)
        }
        pendingSecrets = []
    }

    func discardSecrets() { pendingSecrets = [] }
    func dismissNotices() { notices = [] }

    func pickDocuments() async {
        let urls = await picker.pick(.documents)
        if !urls.isEmpty { await addDocuments(urls) }
    }

    func pickSkillFolder() async {
        let urls = await picker.pick(.skillFolder)
        if !urls.isEmpty { await addSkillFolders(urls) }
    }

    func chooseProject() async {
        guard let url = await picker.pick(.project).first else { return }
        setProject(url)
    }

    /// Complexity: O(d) time, O(d) space
    func makeDraft() -> TaskDraft? {
        guard canStart, let projectRoot else { return nil }
        return TaskDraft(title: DraftTitle.derive(from: prompt), prompt: prompt, projectRoot: projectRoot,
                         documents: documents.map(\.url), skillDirs: skillDirs,
                         startAtCode: startAtCode, useWorktree: useWorktree)
    }

    /// Clears the draft after a start. The project and its skill folders stay for the next task.
    func reset() {
        prompt = ""
        startAtCode = false
        for document in documents { release(document.url) }
        documents = []
        pendingSecrets = []
        notices = []
    }

    /// Ends security-scoped access (view dismissed). The lists stay; `reacquireAccess()` takes access again when the view reappears.
    func releaseAccess() {
        for access in accesses.values { access.release() }
        accesses = [:]
    }

    /// Takes scoped access again for everything still listed (view re-appeared), so the draft survives tab switches.
    /// Complexity: O(d + k) time, O(d + k) space
    func reacquireAccess() {
        for document in documents { acquire(document.url) }
        for dir in skillDirs { acquire(dir) }
    }

    // MARK: - Private

    private func inspectAll(_ urls: [URL]) async -> [(URL, AttachmentInfo?)] {
        var out: [(URL, AttachmentInfo?)] = []
        for url in urls {
            out.append((url, url.isFileURL ? await inspector.inspect(url.standardizedFileURL, policy: policy) : nil))
        }
        return out
    }

    private func documentRejection(_ info: AttachmentInfo) -> DropRejection? {
        switch info.kind {
        case .directory: return .directory
        case .missing: return .missing
        case .file: break
        }
        if !info.isReadable { return .unreadable }
        if info.bytes > policy.maxDocumentBytes { return .tooLarge(bytes: info.bytes) }
        return nil
    }

    private func persistSkillFolders() {
        guard let projectRoot else { return }
        bookmarks.saveSkillFolders(skillDirs, project: projectRoot)
    }

    private func acquire(_ url: URL) {
        let key = url.standardizedFileURL
        guard accesses[key] == nil else { return }
        accesses[key] = ScopedAccess(url: key, hooks: accessHooks)
    }

    private func release(_ url: URL) {
        accesses.removeValue(forKey: url.standardizedFileURL)?.release()
    }
}
