//
//  NotchGeometry.swift
//  LF-AIWorkflow
//

import CoreGraphics

nonisolated enum NotchKind: Sendable, Equatable {
    case notch(width: CGFloat, height: CGFloat)
    case none
}

nonisolated enum NotchGeometry {
    /// Width of the half-circle tab on displays without a notch (TD-004: tune here).
    static let halfCircleWidth: CGFloat = 130
    /// Notch width when the system reports an inset but no auxiliary areas.
    static let fallbackNotchWidth: CGFloat = 200
    /// Menu bar height assumed when a screen reports none.
    static let defaultMenuBarHeight: CGFloat = 24
    static let defaultExpandedSize = CGSize(width: 560, height: 400)

    /// A notch exists when the system reserves a top safe-area inset.
    /// Complexity: O(1) time, O(1) space
    static func kind(for m: ScreenMetrics) -> NotchKind {
        guard m.safeAreaTopInset > 0 else { return .none }
        return .notch(width: notchWidth(m), height: m.safeAreaTopInset)
    }

    /// Exactly the notch rect, or the half-circle tab at the top center when there is no notch.
    /// Complexity: O(1) time, O(1) space
    static func collapsedFrame(for m: ScreenMetrics) -> CGRect {
        let size: CGSize
        switch kind(for: m) {
        case .notch(let width, let height): size = CGSize(width: width, height: height)
        case .none:
            let height = m.menuBarHeight > 0 ? m.menuBarHeight : defaultMenuBarHeight
            size = CGSize(width: halfCircleWidth, height: height)
        }
        return topAnchored(size: size, centerX: notchCenterX(m), in: m.frame)
    }

    /// Top-aligned with the screen, horizontally centered on the notch, clamped inside the screen.
    /// Complexity: O(1) time, O(1) space
    static func expandedFrame(for m: ScreenMetrics, size: CGSize = defaultExpandedSize) -> CGRect {
        topAnchored(size: size, centerX: notchCenterX(m), in: m.frame)
    }

    /// Just below the menu bar, centered under the notch, clamped inside the screen.
    /// Complexity: O(1) time, O(1) space
    static func peekFrame(for m: ScreenMetrics, size: CGSize) -> CGRect {
        let barHeight = max(m.menuBarHeight, m.safeAreaTopInset)
        let top = m.frame.maxY - (barHeight > 0 ? barHeight : defaultMenuBarHeight)
        let clamped = CGSize(width: min(size.width, m.frame.width), height: min(size.height, max(0, top - m.frame.minY)))
        let x = clampedX(centerX: notchCenterX(m), width: clamped.width, in: m.frame)
        return CGRect(x: x, y: top - clamped.height, width: clamped.width, height: clamped.height)
    }

    /// The screen that owns the menu bar: the one whose frame origin is the global origin, else the first.
    /// Complexity: O(n) time, O(1) space
    static func menuBarScreen(_ all: [ScreenMetrics]) -> ScreenMetrics? {
        all.first { $0.frame.origin == .zero } ?? all.first
    }

    // MARK: - Helpers

    private static func notchWidth(_ m: ScreenMetrics) -> CGFloat {
        guard let left = m.auxiliaryTopLeft, let right = m.auxiliaryTopRight else { return fallbackNotchWidth }
        let width = m.frame.width - left.width - right.width
        return width > 0 ? width : fallbackNotchWidth
    }

    private static func notchCenterX(_ m: ScreenMetrics) -> CGFloat {
        guard m.safeAreaTopInset > 0, let left = m.auxiliaryTopLeft, let right = m.auxiliaryTopRight,
              m.frame.width - left.width - right.width > 0 else { return m.frame.midX }
        return (left.maxX + right.minX) / 2
    }

    private static func clampedX(centerX: CGFloat, width: CGFloat, in frame: CGRect) -> CGFloat {
        min(max(centerX - width / 2, frame.minX), frame.maxX - width)
    }

    private static func topAnchored(size: CGSize, centerX: CGFloat, in frame: CGRect) -> CGRect {
        let clamped = CGSize(width: min(size.width, frame.width), height: min(size.height, frame.height))
        return CGRect(x: clampedX(centerX: centerX, width: clamped.width, in: frame),
                      y: frame.maxY - clamped.height, width: clamped.width, height: clamped.height)
    }
}
