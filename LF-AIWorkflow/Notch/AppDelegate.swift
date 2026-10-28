//
//  AppDelegate.swift
//  LF-AIWorkflow
//

import AppKit
import Observation
import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Time the collapse animation needs before the window may shrink (the panel expands BEFORE, shrinks AFTER).
    private static let collapseSettleDelay: Duration = .milliseconds(400)

    private var panel: NotchPanel?
    private var controller: NotchWindowController?
    private var hotkey: GlobalHotkey?
    private var model: WorkflowViewModel?
    private var defaultsObserver: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
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
        model?.stop()
        hotkey?.unregister()
        controller?.stop()
    }

    private func install(model: WorkflowViewModel) {
        self.model = model
        let panel = NotchPanel()
        let hosting = NSHostingView(rootView: NotchRootView(model: model, hover: hover, router: router, layout: layout))
        hosting.sizingOptions = []   // the controller owns the window frame; the content must not resize it
        panel.contentView = hosting
        let controller = NotchWindowController(
            screens: SystemScreenProvider(), override: Self.storedOverride(), panel: panel)
        controller.onKindChange = { [layout] kind in layout.kind = kind }
        controller.apply(.collapsed)
        controller.start()
        panel.orderFrontRegardless()
        self.panel = panel
        self.controller = controller

        let hotkey = GlobalHotkey { [hover] in hover.toggleFromHotkey() }
        if !hotkey.register() {
            AppLog.notch.error("global hotkey option-command-space could not be registered")
        }
        self.hotkey = hotkey

        observePanelState()
        defaultsObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.controller?.setOverride(Self.storedOverride())
            }
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

    /// Growing applies at once; shrinking waits for the collapse animation to finish.
    private func panelStateChanged() {
        let (state, focusHeld) = (hover.state, hover.isFocusHeld)
        frameTask?.cancel()
        let wasOpen = appliedState == .expanded || appliedState == .pinned
        let shrinking = state == .collapsed || state == .peek
        appliedState = state
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
