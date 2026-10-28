//
//  BookmarkStoreTests.swift
//  LF-AIWorkflowTests
//

import Testing
import Foundation
import os
@testable import LF_AIWorkflow

@Suite struct BookmarkStoreTests {
    private func makeStore() -> (BookmarkStore, UserDefaults, String) {
        let suite = "lf-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (BookmarkStore(suiteName: suite), defaults, suite)
    }

    @Test func bookmarkRoundTrips() throws {
        let (store, _, _) = makeStore()
        let dir = try TestEnv.makeTempDir()
        let bookmark = try store.makeBookmark(for: dir)
        let resolved = try store.resolve(bookmark)
        #expect(resolved.url.resolvingSymlinksInPath() == dir.resolvingSymlinksInPath())
        #expect(!resolved.isStale)
    }

    @Test func skillFoldersPersistPerProject() throws {
        let (store, _, suite) = makeStore()
        let (projectA, projectB) = (try TestEnv.makeTempDir(), try TestEnv.makeTempDir())
        let (skillsA, skillsB) = (try TestEnv.makeTempDir(), try TestEnv.makeTempDir())
        store.saveSkillFolders([skillsA], project: projectA)
        store.saveSkillFolders([skillsB], project: projectB)

        let reloaded = BookmarkStore(suiteName: suite)   // a "relaunch" over the same suite
        #expect(reloaded.loadSkillFolders(project: projectA).folders.map { $0.resolvingSymlinksInPath() } == [skillsA.resolvingSymlinksInPath()])
        #expect(reloaded.loadSkillFolders(project: projectB).folders.map { $0.resolvingSymlinksInPath() } == [skillsB.resolvingSymlinksInPath()])
        #expect(reloaded.loadSkillFolders(project: try TestEnv.makeTempDir()).folders.isEmpty)
    }

    @Test func deletedFolderIsDroppedWithAWarningNotACrash() throws {
        let (store, _, _) = makeStore()
        let project = try TestEnv.makeTempDir()
        let keep = try TestEnv.makeTempDir(), gone = try TestEnv.makeTempDir()
        store.saveSkillFolders([keep, gone], project: project)
        try FileManager.default.removeItem(at: gone)

        let loaded = store.loadSkillFolders(project: project)
        #expect(loaded.folders.map { $0.resolvingSymlinksInPath() } == [keep.resolvingSymlinksInPath()])
        #expect(loaded.dropped.count == 1)
        #expect(loaded.dropped[0].contains(gone.lastPathComponent))
        // forgotten: a second load does not warn again
        #expect(store.loadSkillFolders(project: project).dropped.isEmpty)
    }

    @Test func movedFolderResolvesToItsNewLocation() throws {
        let (store, _, _) = makeStore()
        let project = try TestEnv.makeTempDir()
        let parent = try TestEnv.makeTempDir()
        let original = parent.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        store.saveSkillFolders([original], project: project)
        let moved = parent.appendingPathComponent("skills-moved", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)

        let loaded = store.loadSkillFolders(project: project)
        #expect(loaded.folders.map { $0.resolvingSymlinksInPath() } == [moved.resolvingSymlinksInPath()])
        // the refreshed bookmark now points at the new location
        #expect(store.loadSkillFolders(project: project).folders.map { $0.resolvingSymlinksInPath() } == [moved.resolvingSymlinksInPath()])
    }

    @Test func corruptStoredDataIsIgnored() throws {
        let (store, defaults, _) = makeStore()
        let project = try TestEnv.makeTempDir()
        defaults.set(Data("not json".utf8), forKey: BookmarkStore.key(for: project))
        #expect(store.loadSkillFolders(project: project) == SkillFolderLoad(folders: [], dropped: []))
    }

    @Test func savingAnEmptyListClearsTheEntry() throws {
        let (store, defaults, _) = makeStore()
        let project = try TestEnv.makeTempDir()
        store.saveSkillFolders([try TestEnv.makeTempDir()], project: project)
        store.saveSkillFolders([], project: project)
        #expect(defaults.object(forKey: BookmarkStore.key(for: project)) == nil)
    }
}

@Suite struct ScopedAccessTests {
    private final class Counter: Sendable {
        let starts = OSAllocatedUnfairLock(initialState: 0)
        let stops = OSAllocatedUnfairLock(initialState: 0)
        var hooks: ScopedAccess.Hooks {
            ScopedAccess.Hooks(start: { _ in self.starts.withLock { $0 += 1 }; return true },
                               stop: { _ in self.stops.withLock { $0 += 1 } })
        }
    }

    @Test func releaseStopsExactlyOnce() {
        let counter = Counter()
        let access = ScopedAccess(url: URL(fileURLWithPath: "/tmp/x"), hooks: counter.hooks)
        access.release()
        access.release()
        #expect(counter.starts.withLock { $0 } == 1)
        #expect(counter.stops.withLock { $0 } == 1)
    }

    @Test func deinitReleases() {
        let counter = Counter()
        do { _ = ScopedAccess(url: URL(fileURLWithPath: "/tmp/x"), hooks: counter.hooks) }
        #expect(counter.stops.withLock { $0 } == 1)
    }

    @Test func failedStartIsNotStopped() {
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let hooks = ScopedAccess.Hooks(start: { _ in false }, stop: { _ in stops.withLock { $0 += 1 } })
        ScopedAccess(url: URL(fileURLWithPath: "/tmp/x"), hooks: hooks).release()
        #expect(stops.withLock { $0 } == 0)
    }
}
