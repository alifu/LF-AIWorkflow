//
//  ScreenMetrics.swift
//  LF-AIWorkflow
//

import AppKit

/// Plain-value snapshot of an `NSScreen`, so geometry is testable without AppKit screens.
/// Rects are in global AppKit coordinates (origin bottom-left).
nonisolated struct ScreenMetrics: Sendable, Equatable {
    let frame: CGRect
    let safeAreaTopInset: CGFloat
    let auxiliaryTopLeft: CGRect?
    let auxiliaryTopRight: CGRect?
    let menuBarHeight: CGFloat
}

extension ScreenMetrics {
    /// The only AppKit touch point.
    @MainActor
    init(_ screen: NSScreen) {
        let frame = screen.frame
        self.init(
            frame: frame,
            safeAreaTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY))
    }
}
