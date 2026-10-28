//
//  NotchWindowController.swift
//  LF-AIWorkflow
//

import CoreGraphics

/// What the controller needs from the panel; a spy in tests.
protocol PanelFraming: AnyObject {
    var frame: CGRect { get }
    func setFrame(_ frame: CGRect)
    /// Only a keyable panel can take typing focus (composer, pinned).
    func setKeyable(_ isKeyable: Bool)
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

    init(screens: any ScreenProviding, override: DisplayOverride, panel: any PanelFraming) {
        self.screens = screens
        self.override = override
        self.panel = panel
    }

    /// Complexity: O(screens) time, O(1) space
    func apply(_ state: NotchPanelState, focusHeld: Bool = false) {
        self.state = state
        panel.setKeyable(state == .pinned || (focusHeld && state == .expanded))
        place()
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
