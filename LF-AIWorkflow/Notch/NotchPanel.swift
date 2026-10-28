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
        backgroundColor = ThemeColor.clear.nsColor
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Called for Esc when the panel is key. Returns true when the key was used (false while an IME composition is active).
    var onEscape: ((_ isComposingText: Bool) -> Bool)?

    /// Text views send `cancelOperation(_:)` for Esc, but not while an IME composition is active (the IME consumes it).
    override func cancelOperation(_ sender: Any?) {
        if onEscape?(isComposingText) != true { super.cancelOperation(sender) }
    }

    /// Esc reaching the window without a text view (for example focus on a button).
    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        guard event.keyCode == escapeKeyCode, onEscape?(isComposingText) == true else { return super.keyDown(with: event) }
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
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
