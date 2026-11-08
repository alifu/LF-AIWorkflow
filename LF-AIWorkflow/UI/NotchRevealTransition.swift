//
//  NotchRevealTransition.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Grows the panel out of the notch: the content keeps its final layout and a top-anchored mask opens from `start`
/// to the full size, so nothing is re-laid-out or scaled mid-animation. Reversed on removal.
struct NotchReveal: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGSize
    let bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Content fades in over the first part of the reveal so it never shows squashed inside a small mask.
    private static let fadeSpan: CGFloat = 0.6

    func body(content: Content) -> some View {
        content
            .opacity(Double(min(1, max(0, (progress - 0.15) / Self.fadeSpan))))
            .mask(alignment: .top) {
                GeometryReader { proxy in
                    NotchShape(bottomRadius: bottomRadius)
                        .frame(width: lerp(start.width, proxy.size.width), height: lerp(start.height, proxy.size.height))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
}

extension AnyTransition {
    /// Complexity: O(1) time, O(1) space
    static func notchReveal(from start: CGSize, bottomRadius: CGFloat) -> AnyTransition {
        .modifier(active: NotchReveal(progress: 0, start: start, bottomRadius: bottomRadius),
                  identity: NotchReveal(progress: 1, start: start, bottomRadius: bottomRadius))
    }
}
