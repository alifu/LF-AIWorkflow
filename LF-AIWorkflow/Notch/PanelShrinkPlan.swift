//
//  PanelShrinkPlan.swift
//  LF-AIWorkflow
//

/// When the window frame may follow a panel state change. Growing applies at once; shrinking waits for the
/// collapse animation, whose length comes from the same constants the root view animates with.
nonisolated enum PanelShrinkPlan: Sendable, Equatable {
    case applyNow
    case applyAfter(Duration)

    /// Settle time of the spring (response 0.35 s, damping 0.8) used by `NotchRootView`.
    static let springSettle: Duration = .milliseconds(450)
    /// Length of the reduce-motion ease used by `NotchRootView`.
    static let reducedMotionSettle: Duration = .milliseconds(150)

    /// Complexity: O(1) time, O(1) space
    static func decide(from applied: NotchPanelState, to next: NotchPanelState, reduceMotion: Bool) -> PanelShrinkPlan {
        let wasOpen = applied == .expanded || applied == .pinned
        let shrinking = next == .collapsed || next == .peek
        guard wasOpen, shrinking else { return .applyNow }
        return .applyAfter(reduceMotion ? reducedMotionSettle : springSettle)
    }
}

/// The state the window frame was last applied for. Changes are planned against this, not against the last observed
/// state, so a change that arrives while a shrink is still animating waits for the frame that is really on screen.
nonisolated struct PanelFrameTracker: Sendable {
    private(set) var appliedState: NotchPanelState = .collapsed

    /// Complexity: O(1) time, O(1) space
    func plan(for next: NotchPanelState, reduceMotion: Bool) -> PanelShrinkPlan {
        PanelShrinkPlan.decide(from: appliedState, to: next, reduceMotion: reduceMotion)
    }

    /// Complexity: O(1) time, O(1) space
    mutating func markApplied(_ state: NotchPanelState) {
        appliedState = state
    }
}
