//
//  NotchWindowController.swift
//  LF-AIWorkflow
//

import AppKit
import CoreGraphics

/// Seam over the frontmost-app queries so focus restore is testable without a live window server.
@MainActor
protocol FrontmostAppTracking: AnyObject {
    var ownProcessID: pid_t { get }
    func frontmostProcessID() -> pid_t?
    func activate(_ processID: pid_t)
}

/// `NSWorkspace`-backed tracker.
@MainActor
final class SystemFrontmostApp: FrontmostAppTracking {
    var ownProcessID: pid_t { ProcessInfo.processInfo.processIdentifier }
    func frontmostProcessID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    func activate(_ processID: pid_t) {
        NSRunningApplication(processIdentifier: processID)?.activate()
    }
}

/// What the controller needs from the panel; a spy in tests.
protocol PanelFraming: AnyObject {
    var frame: CGRect { get }
    func setFrame(_ frame: CGRect)
    /// A keyable panel can become key (a click inside it does that natively); `takeKey` makes it key now.
    func setKeyable(_ isKeyable: Bool, takeKey: Bool)
}

/// Places the panel for a `NotchPanelState` on the menu-bar screen and follows display changes.
/// Frame changes are immediate; the view layer expands BEFORE its animation starts and shrinks AFTER it ends.
final class NotchWindowController {
    static let peekSize = CGSize(width: 320, height: 96)

    private let screens: any ScreenProviding
    private let panel: any PanelFraming
    private var override: DisplayOverride
    private var state: NotchPanelState = .collapsed
    private var observer: Task<Void, Never>?
    /// Called with the notch kind of the menu-bar screen whenever it is (re)computed.
    var onKindChange: ((NotchKind) -> Void)?
    private var lastKind: NotchKind?
    private let focus: any FrontmostAppTracking
    /// The app that was frontmost when the panel became key (TD-065).
    private var previousApp: pid_t?
    private var isKeyable = false
    private var tookKey = false

    init(screens: any ScreenProviding, override: DisplayOverride, panel: any PanelFraming,
         focus: any FrontmostAppTracking = SystemFrontmostApp()) {
        self.screens = screens
        self.override = override
        self.panel = panel
        self.focus = focus
    }

    /// The panel can become key while expanded or pinned, but is made key at once only for an explicit open (hotkey, click,
    /// pin), never for hover alone. On collapse the previous app gets focus back, but only when this app is frontmost.
    /// Complexity: O(screens) time, O(1) space
    func apply(_ state: NotchPanelState, reason: ExpandReason = .explicit) {
        self.state = state
        updateKeyability(state == .expanded || state == .pinned, takeKey: state == .pinned || reason == .explicit)
        place()
    }

    private func updateKeyability(_ wantsKey: Bool, takeKey: Bool) {
        if wantsKey {
            if !isKeyable { previousApp = focus.frontmostProcessID().flatMap { $0 == focus.ownProcessID ? nil : $0 } }
            let shouldTake = takeKey && !tookKey
            isKeyable = true
            tookKey = tookKey || takeKey
            panel.setKeyable(true, takeKey: shouldTake)
            return
        }
        guard isKeyable else { return }
        isKeyable = false
        tookKey = false
        panel.setKeyable(false, takeKey: false)
        defer { previousApp = nil }
        guard let previous = previousApp, focus.frontmostProcessID() == focus.ownProcessID else { return }
        focus.activate(previous)
    }

    /// Complexity: O(screens) time, O(1) space
    func reposition() { place() }

    func setOverride(_ override: DisplayOverride) {
        self.override = override
        place()
    }

    /// Starts following display changes. Idempotent.
    func start() {
        guard observer == nil else { return }
        let changes = screens.changes
        observer = Task { [weak self] in
            for await _ in changes { self?.reposition() }
        }
    }

    func stop() {
        observer?.cancel()
        observer = nil
    }

    private func place() {
        guard let metrics = NotchGeometry.menuBarScreen(screens.screens).map(override.apply(to:)) else { return }
        let kind = NotchGeometry.kind(for: metrics)
        if kind != lastKind {
            lastKind = kind
            onKindChange?(kind)
        }
        let target: CGRect
        switch state {
        case .collapsed: target = NotchGeometry.collapsedFrame(for: metrics)
        case .peek: target = NotchGeometry.peekFrame(for: metrics, size: Self.peekSize)
        case .expanded, .pinned: target = NotchGeometry.expandedFrame(for: metrics)
        }
        guard target != panel.frame else { return }
        panel.setFrame(target)
    }
}
