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

    /// Fires when the animation toward the given state has finished; the window frame shrinks then.
    var onStateSettled: (NotchPanelState) -> Void = { _ in }

    /// The state the content shows; follows `hover.state` through an animation so completion can be observed.
    @State private var shown: NotchPanelState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(HoverTrackingView(onEnter: hover.pointerEntered, onExit: hover.pointerExited))
            .onChange(of: hover.state) { _, next in
                withAnimation(animation(toward: next), completionCriteria: .logicallyComplete) {
                    shown = next
                } completion: {
                    onStateSettled(next)
                }
            }
            .onChange(of: model.peek) { _, message in
                if message != nil { hover.showPeek(enabled: settings?.peekEnabled ?? true) }
            }
    }

    @ViewBuilder private var content: some View {
        switch shown ?? hover.state {
        case .collapsed:
            // Fixed to the collapsed size: during a close the window is still full-size, and a view that fills it
            // would draw the tab stretched over the whole panel area.
            CollapsedView(kind: layout.kind, summary: model.summary, onActivate: hover.toggleFromHotkey)
                .frame(width: collapsedSize.width, height: collapsedSize.height)
                .transition(.opacity)
        case .peek:
            if let message = model.peek {
                PeekBubble(message: message, pose: pose(for: message), onOpen: { open(message) }, onDismiss: hover.dismissPeek)
                    .transition(popTransition)
            }
        case .expanded, .pinned:
            ExpandedView(model: model, hover: hover, router: router, topInset: layout.topInset)
                .transition(revealTransition)
        }
    }

    /// No overshoot: the window frame clips anything past its edge, so a bouncy spring reads as a stutter.
    private func animation(toward state: NotchPanelState) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        let opening = state == .expanded || state == .pinned
        return .smooth(duration: opening ? Self.openDuration : Self.closeDuration)
    }

    private static let openDuration = 0.32
    private static let closeDuration = 0.24

    private var popTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
    }

    /// The open panel grows out of the notch (or the half-circle tab) and shrinks back into it.
    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .notchReveal(from: collapsedSize, bottomRadius: Self.revealRadius)
    }

    private static let revealRadius: CGFloat = 20

    private var collapsedSize: CGSize {
        switch layout.kind {
        case .notch(let width, let height): CGSize(width: width, height: height)
        case .none: CGSize(width: NotchGeometry.halfCircleWidth, height: NotchGeometry.defaultMenuBarHeight)
        }
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
