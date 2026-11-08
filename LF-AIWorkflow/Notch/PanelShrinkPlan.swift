//
//  PanelShrinkPlan.swift
//  LF-AIWorkflow
//

/// When the window frame may follow a panel state change. Growing applies at once; shrinking waits for the
/// collapse animation to report completion (`NotchRootView` calls back from `withAnimation(completion:)`).
nonisolated enum PanelShrinkPlan: Sendable, Equatable {
    case applyNow
    case awaitAnimationEnd

    /// Safety net: if the animation never reports completion, the pending shrink is applied after this long.
    static let fallbackDeadline: Duration = .seconds(1)

    /// Complexity: O(1) time, O(1) space
    static func decide(from applied: NotchPanelState, to next: NotchPanelState) -> PanelShrinkPlan {
        let wasOpen = applied == .expanded || applied == .pinned
        let shrinking = next == .collapsed || next == .peek
        return wasOpen && shrinking ? .awaitAnimationEnd : .applyNow
    }
}

/// The state the window frame was last applied for. Changes are planned against this, not against the last observed
/// state, so a change that arrives while a shrink is still animating waits for the frame that is really on screen.
nonisolated struct PanelFrameTracker: Sendable {
    private(set) var appliedState: NotchPanelState = .collapsed
    private var pendingShrink: NotchPanelState?

    /// Returns the state whose frame must be applied now, or nil when the shrink has to wait for its animation.
    /// Complexity: O(1) time, O(1) space
    mutating func request(_ next: NotchPanelState) -> NotchPanelState? {
        switch PanelShrinkPlan.decide(from: appliedState, to: next) {
        case .applyNow:
            pendingShrink = nil
            appliedState = next
            return next
        case .awaitAnimationEnd:
            pendingShrink = next
            return nil
        }
    }

    /// The animation toward `state` finished. Returns the frame to apply, once, if that shrink is still the pending one.
    /// Complexity: O(1) time, O(1) space
    mutating func animationFinished(_ state: NotchPanelState) -> NotchPanelState? {
        guard pendingShrink == state else { return nil }
        pendingShrink = nil
        appliedState = state
        return state
    }

    /// The fallback deadline for the shrink toward `state` passed. Same rule as completion, so whichever of the two
    /// arrives first applies the frame and the other is ignored.
    /// Complexity: O(1) time, O(1) space
    mutating func deadlineReached(_ state: NotchPanelState) -> NotchPanelState? {
        animationFinished(state)
    }
}
