//
//  NotchGeometryTests.swift
//  LF-AIWorkflowTests
//

import Testing
import CoreGraphics
@testable import LF_AIWorkflow

enum FakeScreens {
    /// 14" MacBook Pro: 1512x982, notch 184 wide, safe-area inset 32.
    static let mbp14 = notched(CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 184, inset: 32)
    static let mbp16 = notched(CGRect(x: 0, y: 0, width: 1728, height: 1117), notchWidth: 200, inset: 32)
    static let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTopInset: 0,
        auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 24)

    static func notched(_ frame: CGRect, notchWidth: CGFloat, inset: CGFloat) -> ScreenMetrics {
        let side = (frame.width - notchWidth) / 2
        return ScreenMetrics(
            frame: frame, safeAreaTopInset: inset,
            auxiliaryTopLeft: CGRect(x: frame.minX, y: frame.maxY - inset, width: side, height: inset),
            auxiliaryTopRight: CGRect(x: frame.maxX - side, y: frame.maxY - inset, width: side, height: inset),
            menuBarHeight: inset)
    }
}

struct NotchGeometryTests {
    // MARK: kind

    @Test func notchedScreensReportNotchSize() {
        #expect(NotchGeometry.kind(for: FakeScreens.mbp14) == .notch(width: 184, height: 32))
        #expect(NotchGeometry.kind(for: FakeScreens.mbp16) == .notch(width: 200, height: 32))
    }

    @Test func externalScreenHasNoNotch() {
        #expect(NotchGeometry.kind(for: FakeScreens.external) == .none)
    }

    @Test func missingAuxiliaryAreasFallBackToConstantWidth() {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTopInset: 32,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 32)
        #expect(NotchGeometry.kind(for: m) == .notch(width: NotchGeometry.fallbackNotchWidth, height: 32))
        let rect = NotchGeometry.collapsedFrame(for: m)
        #expect(rect.midX == 756)
        #expect(rect.maxY == 982)
    }

    // MARK: collapsed

    @Test func collapsedFrameIsExactlyTheNotch() {
        #expect(NotchGeometry.collapsedFrame(for: FakeScreens.mbp14) == CGRect(x: 664, y: 950, width: 184, height: 32))
        #expect(NotchGeometry.collapsedFrame(for: FakeScreens.mbp16) == CGRect(x: 764, y: 1085, width: 200, height: 32))
    }

    @Test func collapsedFrameOnDisplayLeftOfMainKeepsNegativeOrigin() {
        let m = FakeScreens.notched(CGRect(x: -1512, y: 100, width: 1512, height: 982), notchWidth: 184, inset: 32)
        let rect = NotchGeometry.collapsedFrame(for: m)
        #expect(rect == CGRect(x: -848, y: 1050, width: 184, height: 32))
    }

    @Test func noNotchGetsHalfCircleTabCenteredAtTop() {
        let rect = NotchGeometry.collapsedFrame(for: FakeScreens.external)
        #expect(rect.width == NotchGeometry.halfCircleWidth)
        #expect(rect.height == 24)
        #expect(rect.midX == 960)
        #expect(rect.maxY == 1080)
    }

    @Test func noNotchWithoutMenuBarHeightUsesDefault() {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), safeAreaTopInset: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 0)
        #expect(NotchGeometry.collapsedFrame(for: m).height == NotchGeometry.defaultMenuBarHeight)
    }

    // MARK: expanded

    @Test func expandedFrameIsTopAlignedAndCenteredOnTheNotch() {
        let rect = NotchGeometry.expandedFrame(for: FakeScreens.mbp14)
        #expect(rect == CGRect(x: 476, y: 582, width: 560, height: 400))
        #expect(rect.maxY == FakeScreens.mbp14.frame.maxY)
        #expect(rect.midX == NotchGeometry.collapsedFrame(for: FakeScreens.mbp14).midX)
    }

    @Test func expandedFrameClampsToNarrowScreen() {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 400, height: 300), safeAreaTopInset: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 24)
        let rect = NotchGeometry.expandedFrame(for: m)
        #expect(rect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func expandedFrameStaysInsideFrameOnOffsetDisplay() {
        let m = FakeScreens.notched(CGRect(x: -1512, y: 100, width: 1512, height: 982), notchWidth: 184, inset: 32)
        let rect = NotchGeometry.expandedFrame(for: m)
        #expect(m.frame.contains(rect))
        #expect(rect.maxY == m.frame.maxY)
    }

    // MARK: peek

    @Test func peekFrameSitsBelowMenuBarCenteredAndClearOfCollapsed() {
        let size = CGSize(width: 300, height: 80)
        let rect = NotchGeometry.peekFrame(for: FakeScreens.mbp14, size: size)
        let collapsed = NotchGeometry.collapsedFrame(for: FakeScreens.mbp14)
        #expect(rect == CGRect(x: 606, y: 870, width: 300, height: 80))
        #expect(rect.midX == collapsed.midX)
        #expect(!rect.intersects(collapsed))
    }

    @Test func peekFrameOnNonNotchScreenUsesMenuBarHeight() {
        let rect = NotchGeometry.peekFrame(for: FakeScreens.external, size: CGSize(width: 300, height: 80))
        #expect(rect.maxY == 1056, "rect=\(rect)")
        #expect(rect.midX == 960)
    }

    @Test func peekFrameClampsToScreen() {
        let rect = NotchGeometry.peekFrame(for: FakeScreens.external, size: CGSize(width: 5000, height: 5000))
        #expect(FakeScreens.external.frame.contains(rect))
    }

    // MARK: menu bar screen

    @Test func menuBarScreenIsTheOneAtTheOrigin() {
        let side = FakeScreens.notched(CGRect(x: -1512, y: 0, width: 1512, height: 982), notchWidth: 184, inset: 32)
        #expect(NotchGeometry.menuBarScreen([side, FakeScreens.external]) == FakeScreens.external)
    }

    @Test func menuBarScreenFallsBackToFirstAndNilWhenEmpty() {
        let shifted = FakeScreens.notched(CGRect(x: 10, y: 10, width: 1512, height: 982), notchWidth: 184, inset: 32)
        #expect(NotchGeometry.menuBarScreen([shifted, FakeScreens.mbp16.withFrameOrigin(x: 5, y: 5)]) == shifted)
        #expect(NotchGeometry.menuBarScreen([]) == nil)
    }
}

extension ScreenMetrics {
    func withFrameOrigin(x: CGFloat, y: CGFloat) -> ScreenMetrics {
        ScreenMetrics(frame: CGRect(x: x, y: y, width: frame.width, height: frame.height),
                      safeAreaTopInset: safeAreaTopInset, auxiliaryTopLeft: auxiliaryTopLeft,
                      auxiliaryTopRight: auxiliaryTopRight, menuBarHeight: menuBarHeight)
    }
}
