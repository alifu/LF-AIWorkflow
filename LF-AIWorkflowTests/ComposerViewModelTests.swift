//
//  ComposerViewModelTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

/// Reports what the test says; never touches the disk.
struct FakeInspector: AttachmentInspecting {
    var infos: [String: AttachmentInfo] = [:]
    func inspect(_ url: URL, policy: AttachmentPolicy) async -> AttachmentInfo {
        infos[url.lastPathComponent] ?? AttachmentInfo(url: url, kind: .file, bytes: 100, isReadable: true, inlineTokens: 10)
    }
}

final class FakeBookmarks: BookmarkStoring, Sendable {
    private let store = OSAllocatedUnfairLock(initialState: [String: [URL]]())
    private let droppedOnLoad = OSAllocatedUnfairLock(initialState: [String]())
    func seed(_ folders: [URL], project: URL, dropped: [String] = []) {
        store.withLock { $0[project.standardizedFileURL.path] = folders }
        droppedOnLoad.withLock { $0 = dropped }
    }
    func saved(project: URL) -> [URL]? { store.withLock { $0[project.standardizedFileURL.path] } }
    func makeBookmark(for url: URL) throws -> ScopedBookmark { ScopedBookmark(url: url, data: Data()) }
    func resolve(_ bookmark: ScopedBookmark) throws -> ResolvedBookmark { ResolvedBookmark(url: bookmark.url, isStale: false) }
    func loadSkillFolders(project: URL) -> SkillFolderLoad {
        SkillFolderLoad(folders: store.withLock { $0[project.standardizedFileURL.path] } ?? [], dropped: droppedOnLoad.withLock { $0 })
    }
    func saveSkillFolders(_ folders: [URL], project: URL) { store.withLock { $0[project.standardizedFileURL.path] = folders } }
}

@MainActor
final class FakePicker: FilePicking {
    var results: [PickRequest: [URL]] = [:]
    private(set) var requests: [PickRequest] = []
    func pick(_ request: PickRequest) async -> [URL] { requests.append(request); return results[request] ?? [] }
}

@MainActor
@Suite struct ComposerViewModelTests {
    private let project = URL(fileURLWithPath: "/tmp/MyApp", isDirectory: true)
    private let starts = OSAllocatedUnfairLock(initialState: 0)
    private let stops = OSAllocatedUnfairLock(initialState: 0)

    private func make(inspector: FakeInspector = FakeInspector(), policy: AttachmentPolicy = .standard,
                      bookmarks: FakeBookmarks = FakeBookmarks(), picker: FakePicker = FakePicker())
        -> (ComposerViewModel, FakeBookmarks, FakePicker) {
        let (starts, stops) = (self.starts, self.stops)
        let hooks = ScopedAccess.Hooks(start: { _ in starts.withLock { $0 += 1 }; return true },
                                       stop: { _ in stops.withLock { $0 += 1 } })
        let vm = ComposerViewModel(bookmarks: bookmarks, picker: picker, inspector: inspector, policy: policy,
                                   estimator: { $0.count }, accessHooks: hooks)
        return (vm, bookmarks, picker)
    }

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/docs/\(name)") }

    // MARK: documents

    @Test func addsDedupesAndRemoves() async {
        let (vm, _, _) = make()
        let rejected = await vm.addDocuments([file("a.md"), file("b.md"), file("a.md"), URL(fileURLWithPath: "/tmp/docs/../docs/b.md")])
        #expect(vm.documents.map(\.name) == ["a.md", "b.md"])
        #expect(rejected.map(\.reason) == [.duplicate, .duplicate])
        #expect(await vm.addDocuments([file("a.md")]).map(\.reason) == [.duplicate])
        vm.removeDocument(file("a.md"))
        #expect(vm.documents.map(\.name) == ["b.md"])
    }

    @Test func rejectsNonFileURLsDirectoriesMissingAndUnreadable() async {
        var infos: [String: AttachmentInfo] = [:]
        infos["dir"] = AttachmentInfo(url: file("dir"), kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0)
        infos["gone.md"] = AttachmentInfo(url: file("gone.md"), kind: .missing, bytes: 0, isReadable: false, inlineTokens: 0)
        infos["locked.md"] = AttachmentInfo(url: file("locked.md"), kind: .file, bytes: 5, isReadable: false, inlineTokens: 0)
        let (vm, _, _) = make(inspector: FakeInspector(infos: infos))
        let rejected = await vm.addDocuments([URL(string: "https://example.com/a.md")!, file("dir"), file("gone.md"), file("locked.md"), file("ok.md")])
        #expect(rejected.map(\.reason) == [.notFileURL, .directory, .missing, .unreadable])
        #expect(vm.documents.map(\.name) == ["ok.md"])
        #expect(vm.notices.count == 4)
    }

    @Test func capsSizeAndCount() async {
        let big = AttachmentInfo(url: file("big.pdf"), kind: .file, bytes: 6_000_000, isReadable: true, inlineTokens: 0)
        let policy = AttachmentPolicy(maxDocuments: 2, maxDocumentBytes: 5_000_000, maxSkillFolders: 5, inlineMaxTokens: 2000)
        let (vm, _, _) = make(inspector: FakeInspector(infos: ["big.pdf": big]), policy: policy)
        let rejected = await vm.addDocuments([file("big.pdf"), file("a.md"), file("b.md"), file("c.md")])
        #expect(rejected.map(\.reason) == [.tooLarge(bytes: 6_000_000), .limitReached(max: 2)])
        #expect(vm.documents.map(\.name) == ["a.md", "b.md"])
        #expect(vm.notices.contains { $0.contains("big.pdf") && $0.contains("MB") })
        #expect(vm.notices.contains { $0.contains("2") })
    }

    // MARK: secrets

    @Test func secretFilesWaitForConfirmation() async {
        let (vm, _, _) = make()
        let rejected = await vm.addDocuments([file(".env"), file("a.md"), file("deploy.pem")])
        #expect(rejected.isEmpty)
        #expect(vm.documents.map(\.name) == ["a.md"])
        #expect(vm.pendingSecrets.map(\.name) == [".env", "deploy.pem"])
        vm.confirmSecrets()
        #expect(vm.documents.map(\.name) == ["a.md", ".env", "deploy.pem"])
        #expect(vm.pendingSecrets.isEmpty)
    }

    @Test func discardingSecretsAttachesNothing() async {
        let (vm, _, _) = make()
        await vm.addDocuments([file("id_rsa")])
        vm.discardSecrets()
        #expect(vm.documents.isEmpty && vm.pendingSecrets.isEmpty)
    }

    @Test func confirmedSecretsStillRespectTheCountCap() async {
        let policy = AttachmentPolicy(maxDocuments: 1, maxDocumentBytes: 5_000_000, maxSkillFolders: 5, inlineMaxTokens: 2000)
        let (vm, _, _) = make(policy: policy)
        await vm.addDocuments([file(".env"), file("x.md")])
        vm.confirmSecrets()
        #expect(vm.documents.count == 1)
    }

    // MARK: skill folders

    @Test func skillFolderRejectsFilesAndPersistsPerProject() async {
        var infos: [String: AttachmentInfo] = [:]
        infos["skills"] = AttachmentInfo(url: file("skills"), kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0)
        let (vm, bookmarks, _) = make(inspector: FakeInspector(infos: infos))
        vm.setProject(project)
        let rejected = await vm.addSkillFolders([file("skills"), file("notes.md")])
        #expect(rejected.map(\.reason) == [.notDirectory])
        #expect(vm.skillDirs.map(\.lastPathComponent) == ["skills"])
        #expect(bookmarks.saved(project: project)?.map(\.lastPathComponent) == ["skills"])
    }

    @Test func settingTheProjectLoadsRememberedFoldersAndWarnsAboutDroppedOnes() {
        let bookmarks = FakeBookmarks()
        bookmarks.seed([file("skills")], project: project, dropped: ["/old/skills"])
        let (vm, _, _) = make(bookmarks: bookmarks)
        vm.setProject(project)
        #expect(vm.skillDirs.map(\.lastPathComponent) == ["skills"])
        #expect(vm.notices.contains { $0.contains("/old/skills") })
    }

    @Test func switchingProjectSwapsRememberedFolders() {
        let other = URL(fileURLWithPath: "/tmp/Other", isDirectory: true)
        let bookmarks = FakeBookmarks()
        bookmarks.seed([file("a")], project: project)
        bookmarks.seed([file("b")], project: other)
        let (vm, _, _) = make(bookmarks: bookmarks)
        vm.setProject(project)
        vm.setProject(other)
        #expect(vm.skillDirs.map(\.lastPathComponent) == ["b"])
    }

    @Test func removeSkillFolderForgetsIt() async {
        var infos: [String: AttachmentInfo] = [:]
        infos["skills"] = AttachmentInfo(url: file("skills"), kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0)
        let (vm, bookmarks, _) = make(inspector: FakeInspector(infos: infos))
        vm.setProject(project)
        await vm.addSkillFolders([file("skills")])
        vm.removeSkillFolder(file("skills"))
        #expect(vm.skillDirs.isEmpty)
        #expect(bookmarks.saved(project: project) == [])
    }

    @Test func skillFolderCountIsCapped() async {
        var infos: [String: AttachmentInfo] = [:]
        for n in ["a", "b", "c"] { infos[n] = AttachmentInfo(url: file(n), kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0) }
        let policy = AttachmentPolicy(maxDocuments: 5, maxDocumentBytes: 100, maxSkillFolders: 2, inlineMaxTokens: 10)
        let (vm, _, _) = make(inspector: FakeInspector(infos: infos), policy: policy)
        let rejected = await vm.addSkillFolders([file("a"), file("b"), file("c")])
        #expect(rejected.map(\.reason) == [.limitReached(max: 2)])
    }

    // MARK: pickers

    @Test func pickersFeedTheSamePath() async {
        let picker = FakePicker()
        picker.results[.documents] = [file("a.md"), file("b.md")]
        picker.results[.project] = [project]
        let (vm, _, _) = make(picker: picker)
        await vm.pickDocuments()
        await vm.chooseProject()
        #expect(vm.documents.count == 2)
        #expect(vm.projectRoot == project)
        #expect(picker.requests == [.documents, .project])
    }

    @Test func cancelledPickerChangesNothing() async {
        let (vm, _, picker) = make()
        await vm.pickDocuments()
        await vm.pickSkillFolder()
        await vm.chooseProject()
        #expect(vm.documents.isEmpty && vm.skillDirs.isEmpty && vm.projectRoot == nil)
        #expect(picker.requests.count == 3)
    }

    // MARK: start, draft, estimate

    @Test func canStartNeedsPromptAndProject() {
        let (vm, _, _) = make()
        #expect(!vm.canStart)
        vm.prompt = "  \n "
        vm.setProject(project)
        #expect(!vm.canStart)
        vm.prompt = "Add dark mode"
        #expect(vm.canStart)
        vm.setProject(nil)
        #expect(!vm.canStart)
    }

    @Test func makeDraftCarriesEverything() async {
        let (vm, _, _) = make()
        vm.setProject(project)
        vm.prompt = "  Add dark mode\nwith a toggle"
        await vm.addDocuments([file("a.md")])
        let draft = vm.makeDraft()
        #expect(draft?.title == "Add dark mode")
        #expect(draft?.prompt == "  Add dark mode\nwith a toggle")
        #expect(draft?.projectRoot == project)
        #expect(draft?.documents == [file("a.md")])
    }

    @Test func defaultDraftDoesNotUseAWorktree() {
        let (vm, _, _) = make()
        vm.setProject(project)
        vm.prompt = "Do a thing"
        #expect(vm.useWorktree == false)
        #expect(vm.makeDraft()?.useWorktree == false)
    }

    @Test func makeDraftIsNilWhenCannotStart() {
        let (vm, _, _) = make()
        #expect(vm.makeDraft() == nil)
    }

    @Test func longTitleIsTruncated() {
        let (vm, _, _) = make()
        vm.setProject(project)
        vm.prompt = String(repeating: "x", count: 200)
        #expect(vm.makeDraft()?.title.count == DraftTitle.maxLength)
    }

    @Test func estimateCountsPromptAndInlineDocuments() async {
        let big = AttachmentInfo(url: file("big.md"), kind: .file, bytes: 90_000, isReadable: true, inlineTokens: 0)
        let small = AttachmentInfo(url: file("small.md"), kind: .file, bytes: 400, isReadable: true, inlineTokens: 120)
        let (vm, _, _) = make(inspector: FakeInspector(infos: ["big.md": big, "small.md": small]))
        vm.prompt = "12345"          // estimator in this test is the character count
        #expect(vm.estimatedTokens == 5)
        await vm.addDocuments([file("big.md"), file("small.md")])
        #expect(vm.estimatedTokens == 125)
        vm.prompt = "1234567890"
        #expect(vm.estimatedTokens == 130)
        vm.removeDocument(file("small.md"))
        #expect(vm.estimatedTokens == 10)
    }

    @Test func resetClearsTheDraftButKeepsTheProjectAndSkillFolders() async {
        var infos: [String: AttachmentInfo] = [:]
        infos["skills"] = AttachmentInfo(url: file("skills"), kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0)
        let (vm, _, _) = make(inspector: FakeInspector(infos: infos))
        vm.setProject(project)
        vm.prompt = "x"
        await vm.addDocuments([file("a.md"), file(".env")])
        await vm.addSkillFolders([file("skills")])
        vm.reset()
        #expect(vm.prompt.isEmpty && vm.documents.isEmpty && vm.pendingSecrets.isEmpty && vm.notices.isEmpty)
        #expect(vm.projectRoot == project)
        #expect(vm.skillDirs.count == 1)
    }

    // MARK: scoped access

    @Test func accessIsBalancedAcrossAddRemoveAndRelease() async {
        let (vm, _, _) = make()
        await vm.addDocuments([file("a.md"), file("b.md"), file("c.md")])
        #expect(starts.withLock { $0 } == 3)
        vm.removeDocument(file("a.md"))
        #expect(stops.withLock { $0 } == 1)
        vm.releaseAccess()
        #expect(stops.withLock { $0 } == 3)
        vm.releaseAccess()
        #expect(stops.withLock { $0 } == 3)
    }

    @Test func dismissKeepsTheListedFiles() async {
        let (vm, _, _) = make()
        await vm.addDocuments([file("a.md")])
        vm.releaseAccess()
        #expect(vm.documents.count == 1)
    }

    @Test func reacquiringAccessAfterReleaseKeepsTheDraftUsable() async {
        let skills = URL(fileURLWithPath: "/tmp/skills", isDirectory: true)
        let dirInfo = AttachmentInfo(url: skills, kind: .directory, bytes: 0, isReadable: true, inlineTokens: 0)
        let (vm, _, _) = make(inspector: FakeInspector(infos: ["skills": dirInfo]))
        await vm.addDocuments([file("a.md")])
        await vm.addSkillFolders([skills])
        #expect(starts.withLock { $0 } == 2)
        vm.releaseAccess()
        #expect(stops.withLock { $0 } == 2)
        vm.reacquireAccess()
        #expect(starts.withLock { $0 } == 4)
        vm.reacquireAccess()
        #expect(starts.withLock { $0 } == 4)
        vm.releaseAccess()
        #expect(stops.withLock { $0 } == 4)
    }

    @Test func symlinkToASecretNeedsConfirmation() async throws {
        let dir = try TestEnv.makeTempDir()
        try TestEnv.write(dir, ".ssh/id_rsa", "k")
        let link = dir.appendingPathComponent("notes.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent(".ssh/id_rsa"))
        let (vm, _, _) = make()
        await vm.addDocuments([link])
        #expect(vm.documents.isEmpty)
        #expect(vm.pendingSecrets.map(\.name) == ["notes.txt"])
    }

    @Test func noticesCanBeDismissed() async {
        let (vm, _, _) = make()
        await vm.addDocuments([file("a.md"), file("a.md")])
        #expect(!vm.notices.isEmpty)
        vm.dismissNotices()
        #expect(vm.notices.isEmpty)
    }
}
