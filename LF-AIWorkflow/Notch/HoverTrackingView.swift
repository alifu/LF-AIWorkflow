//
//  HoverTrackingView.swift
//  LF-AIWorkflow
//

import AppKit
import SwiftUI

/// Reports pointer enter/exit over its bounds. No logic here: `HoverController` decides what it means.
struct HoverTrackingView: NSViewRepresentable {
    let onEnter: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onEnter = onEnter
        view.onExit = onExit
        return view
    }

    func updateNSView(_ view: TrackingNSView, context: Context) {
        view.onEnter = onEnter
        view.onExit = onExit
    }

    final class TrackingNSView: NSView {
        var onEnter: () -> Void = {}
        var onExit: () -> Void = {}

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onEnter() }
        override func mouseExited(with event: NSEvent) { onExit() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never swallow clicks meant for content
        override var isOpaque: Bool { false }
    }
}

#Preview {
    HoverTrackingView(onEnter: {}, onExit: {})
        .frame(width: 120, height: 40)
}
