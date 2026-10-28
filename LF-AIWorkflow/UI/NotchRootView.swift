//
//  NotchRootView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Root of the panel: picks collapsed, peek or expanded from `HoverController.state` and animates between them.
/// The window frame already matches the state (the controller expands it before and shrinks it after the animation).
struct NotchRootView: View {
    let model: any WorkflowControlling
    let hover: HoverController
    let router: PanelRouter
    let layout: NotchLayoutModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(HoverTrackingView(onEnter: hover.pointerEntered, onExit: hover.pointerExited))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8),
                       value: hover.state)
            .onChange(of: model.peek) { _, message in
                if message != nil { hover.showPeek(enabled: settings?.peekEnabled ?? true) }
            }
    }

    @ViewBuilder private var content: some View {
        switch hover.state {
        case .collapsed:
            CollapsedView(kind: layout.kind, summary: model.summary, onActivate: hover.toggleFromHotkey)
                .transition(.opacity)
        case .peek:
            if let message = model.peek {
                PeekBubble(message: message, pose: pose(for: message), onOpen: { open(message) }, onDismiss: hover.dismissPeek)
                    .transition(popTransition)
            }
        case .expanded, .pinned:
            ExpandedView(model: model, hover: hover, router: router, topInset: layout.topInset)
                .transition(popTransition)
        }
    }

    private var popTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
    }

    private func open(_ message: PeekMessage) {
        if message.kind == .info {
            router.tab = .new
            router.composerMode = .research
        } else {
            router.show(task: message.taskID)
        }
        hover.expand()
    }

    private func pose(for message: PeekMessage) -> MascotPose {
        switch message.kind {
        case .planReady, .needsInput, .info: .attention
        case .failed: .error
        case .done: .done
        }
    }
}

#if DEBUG
#Preview("Expanded") {
    let hover = HoverController()
    hover.toggleFromHotkey()
    return NotchRootView(model: PreviewModel(), hover: hover, router: PanelRouter(), layout: NotchLayoutModel(kind: .notch(width: 200, height: 32)))
        .frame(width: 560, height: 400)
}

#Preview("Collapsed, no notch") {
    NotchRootView(model: PreviewModel(), hover: HoverController(), router: PanelRouter(), layout: NotchLayoutModel(kind: .none))
        .frame(width: NotchGeometry.halfCircleWidth, height: 24)
}
#endif
