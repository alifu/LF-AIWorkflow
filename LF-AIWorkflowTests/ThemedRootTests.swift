//
//  ThemedRootTests.swift
//  LF-AIWorkflowTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_AIWorkflow

@MainActor
struct ThemedRootTests {
    private func makeStore() -> SettingsStore {
        SettingsStore(suiteName: "ThemedRootTests-\(UUID().uuidString)")
    }

    @Test func classicStyleMapsToTheClassicTheme() {
        let store = makeStore()
        store.artStyle = .classic
        #expect(store.theme == .classic)
    }

    @Test func themeFollowsTheArtStyleSetting() {
        let store = makeStore()
        store.artStyle = .popArt
        #expect(store.theme.id == .popArt)
        #expect(store.theme == .popArt)
    }

    @Test func appearanceNamesMapToAppKit() {
        #expect(AppearanceChoice.system.nsAppearanceName == nil)
        #expect(AppearanceChoice.light.nsAppearanceName == .aqua)
        #expect(AppearanceChoice.dark.nsAppearanceName == .darkAqua)
    }

    @Test func applyingAppearanceSetsTheViewAndClearsItForSystem() {
        let view = NSView()
        AppearanceApplier.apply(.dark, to: view)
        #expect(view.appearance?.name == .darkAqua)
        AppearanceApplier.apply(.light, to: view)
        #expect(view.appearance?.name == .aqua)
        AppearanceApplier.apply(.system, to: view)
        #expect(view.appearance == nil)
    }

    @Test func applyingAppearanceAlsoReachesAPanel() {
        let panel = NotchPanel()
        AppearanceApplier.apply(.dark, to: panel)
        #expect(panel.appearance?.name == .darkAqua)
    }

    @Test func observerAppliesTheCurrentAndEveryLaterChoice() async {
        let store = makeStore()
        store.appearance = .dark
        let view = NSView()
        let observer = AppearanceObserver(settings: store, targets: [view])
        #expect(view.appearance?.name == .darkAqua)
        store.appearance = .light
        for _ in 0..<50 where view.appearance?.name != .aqua { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) }
        #expect(view.appearance?.name == .aqua)
        withExtendedLifetime(observer) {}
    }

    @Test func themedRootHostsItsContent() {
        let store = makeStore()
        let hosting = NSHostingView(rootView: ThemedRoot(settings: store) { Text("x") })
        #expect(hosting.fittingSize.width > 0)
    }

    @Test func sharedStoreIsOneInstance() {
        #expect(AppComposition.settings === AppComposition.settings)
    }
}
