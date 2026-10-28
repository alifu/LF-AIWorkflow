//
//  AppDelegate.swift
//  LF-AIWorkflow
//

import AppKit
import Observation
import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Settings edits arrive in bursts (typing a number); the engine gets the last value after this quiet period.
    private static let settingsDebounce: Duration = .milliseconds(300)
    /// Time the collapse animation needs before the window may shrink (the panel expands BEFORE, shrinks AFTER).
    private static let collapseSettleDelay: Duration = .milliseconds(400)

    private var panel: NotchPanel?
    private var controller: NotchWindowController?
    private var hotkeys: HotkeyManager?
    private let clickOutside = ClickOutsideMonitor()
    private var model: WorkflowViewModel?
    private var appearanceObserver: AppearanceObserver?
    private var defaultsObserver: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var engineSettingsTask: Task<Void, Never>?
    private var appliedState: NotchPanelState = .collapsed
    private let hover = HoverController()
    private let router = PanelRouter()
    private let layout = NotchLayoutModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { [weak self] in
            let model = await AppComposition.makeViewModel()
            self?.install(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        defaultsObserver?.cancel()
        frameTask?.cancel()
        engineSettingsTask?.cancel()
        model?.stop()
        hotkeys?.stop()
        clickOutside.stop()
        controller?.stop()
    }

    private func install(model: WorkflowViewModel) {
        self.model = model
        let panel = NotchPanel()
        let (hover, router, layout) = (self.hover, self.router, self.layout)
        let hosting = NSHostingView(rootView: ThemedRoot(settings: AppComposition.settings) {
            NotchRootView(model: model, hover: hover, router: router, layout: layout)
        })
        hosting.sizingOptions = []   // the controller owns the window frame; the content must not resize it
        panel.contentView = hosting
        appearanceObserver = AppearanceObserver(settings: AppComposition.settings, targets: [panel, hosting])
        let controller = NotchWindowController(
            screens: SystemScreenProvider(), override: Self.storedOverride(), panel: panel)
        controller.onKindChange = { [layout] kind in layout.kind = kind }
        controller.apply(.collapsed)
        controller.start()
        panel.orderFrontRegardless()
        self.panel = panel
        self.controller = controller

        panel.onEscape = { [hover] composing in hover.escapePressed(isComposingText: composing) }
        let hotkeys = HotkeyManager(
            factory: { spec, action in GlobalHotkey(spec: spec, action: action) },
            action: { [hover] in hover.toggleFromHotkey() })
        self.hotkeys = hotkeys
        applyHotkey()

        observePanelState()
        observeEngineSettings()
        defaultsObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.controller?.setOverride(Self.storedOverride())
            }
        }
    }

    /// Registers the stored hotkey, publishes the outcome for the UI, and re-arms itself on the next change.
    private func applyHotkey() {
        let settings = AppComposition.settings
        let spec = withObservationTracking {
            settings.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyHotkey() }
        }
        let registered = hotkeys?.apply(spec) ?? false
        settings.hotkeyRegistered = registered
        if !registered { AppLog.notch.error("global hotkey \(spec.displayString, privacy: .public) could not be registered") }
    }

    /// Re-arms itself after every settings change and hands the engine a fresh copy (new tasks only).
    private func observeEngineSettings() {
        withObservationTracking {
            _ = AppComposition.settings.snapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleEngineSettings()
                self?.observeEngineSettings()
            }
        }
    }

    private func scheduleEngineSettings() {
        engineSettingsTask?.cancel()
        engineSettingsTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.settingsDebounce) } catch { return }
            guard let self, let model = self.model else { return }
            await model.applySettings(EngineSettings.from(AppComposition.settings.snapshot()))
        }
    }

    /// Re-arms itself after every change of the observed hover state.
    private func observePanelState() {
        withObservationTracking {
            _ = hover.state
            _ = hover.isFocusHeld
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.panelStateChanged()
                self?.observePanelState()
            }
        }
    }

    /// The global click monitor runs only while the panel is expanded (pinned panels ignore outside clicks anyway).
    private func updateClickOutside(for state: NotchPanelState) {
        if state == .expanded {
            clickOutside.start { [hover] in hover.clickedOutside() }
        } else {
            clickOutside.stop()
        }
    }

    /// Growing applies at once; shrinking waits for the collapse animation to finish.
    private func panelStateChanged() {
        let (state, focusHeld) = (hover.state, hover.isFocusHeld)
        frameTask?.cancel()
        let wasOpen = appliedState == .expanded || appliedState == .pinned
        let shrinking = state == .collapsed || state == .peek
        appliedState = state
        updateClickOutside(for: state)
        guard wasOpen, shrinking else {
            controller?.apply(state, focusHeld: focusHeld)
            return
        }
        frameTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.collapseSettleDelay) } catch { return }
            self?.controller?.apply(state, focusHeld: focusHeld)
        }
    }

    private static func storedOverride() -> DisplayOverride {
        DisplayOverride.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            stored: UserDefaults.standard.string(forKey: DisplayOverride.defaultsKey))
    }
}
