//
//  NotchPanel.swift
//  LF-AIWorkflow
//

import AppKit

/// Borderless, non-activating, always-on-top panel that lives in the notch area.
final class NotchPanel: NSPanel, PanelFraming {
    private var allowsKey = false
    private var wasKeyable = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .statusBar
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    func setFrame(_ frame: CGRect) { setFrame(frame, display: true) }

    private(set) var resignKeyCount = 0
    override func resignKey() { resignKeyCount += 1; super.resignKey() }

    func setKeyable(_ isKeyable: Bool) {
        allowsKey = isKeyable
        if isKeyable {
            makeKeyAndOrderFront(nil)
        } else if wasKeyable || isKeyWindow {
            resignKey()
        }
        wasKeyable = isKeyable
    }
}
