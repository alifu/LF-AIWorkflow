//
//  NotchWindowControllerTests.swift
//  LF-AIWorkflowTests
//

import Testing
import CoreGraphics
@testable import LF_AIWorkflow

final class FakeScreenProvider: ScreenProviding {
    var screens: [ScreenMetrics]
    let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(_ screens: [ScreenMetrics]) {
        self.screens = screens
        (changes, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func fireChange() { continuation.yield() }
}

@MainActor
final class SpyPanel: PanelFraming {
    private(set) var frame: CGRect = .zero
    private(set) var setFrameCount = 0
    private(set) var keyable = false
    let frames: AsyncStream<CGRect>
    private let continuation: AsyncStream<CGRect>.Continuation

    init() { (frames, continuation) = AsyncStream.makeStream(of: CGRect.self) }

    func setFrame(_ frame: CGRect) {
        self.frame = frame
        setFrameCount += 1
        continuation.yield(frame)
    }

    func setKeyable(_ isKeyable: Bool) { keyable = isKeyable }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NotchWindowControllerTests {
    private func make(_ screens: [ScreenMetrics], override: DisplayOverride = .auto)
        -> (NotchWindowController, FakeScreenProvider, SpyPanel) {
        let provider = FakeScreenProvider(screens)
        let panel = SpyPanel()
        return (NotchWindowController(screens: provider, override: override, panel: panel), provider, panel)
    }

    @Test func stateMapsToTheExpectedFrames() {
        let (controller, _, panel) = make([FakeScreens.mbp14])
        controller.apply(.collapsed)
        #expect(panel.frame == NotchGeometry.collapsedFrame(for: FakeScreens.mbp14))
        controller.apply(.expanded)
        #expect(panel.frame == NotchGeometry.expandedFrame(for: FakeScreens.mbp14))
        controller.apply(.pinned)
        #expect(panel.frame == NotchGeometry.expandedFrame(for: FakeScreens.mbp14))
        controller.apply(.peek)
        #expect(panel.frame == NotchGeometry.peekFrame(for: FakeScreens.mbp14, size: NotchWindowController.peekSize))
    }

    @Test func picksTheMenuBarScreen() {
        let side = FakeScreens.notched(CGRect(x: -1512, y: 0, width: 1512, height: 982), notchWidth: 184, inset: 32)
        let (controller, _, panel) = make([side, FakeScreens.external])
        controller.apply(.collapsed)
        #expect(panel.frame == NotchGeometry.collapsedFrame(for: FakeScreens.external))
    }

    @Test func appliesTheDisplayOverride() {
        let (controller, _, panel) = make([FakeScreens.mbp14], override: .noNotch)
        controller.apply(.collapsed)
        #expect(panel.frame.width == NotchGeometry.halfCircleWidth)
        controller.setOverride(.auto)
        #expect(panel.frame == NotchGeometry.collapsedFrame(for: FakeScreens.mbp14))
    }

    @Test func doesNotResetTheFrameWhenUnchanged() {
        let (controller, _, panel) = make([FakeScreens.mbp14])
        controller.apply(.collapsed)
        controller.apply(.collapsed)
        controller.reposition()
        #expect(panel.setFrameCount == 1)
    }

    @Test func noScreensIsANoOp() {
        let (controller, _, panel) = make([])
        controller.apply(.expanded)
        #expect(panel.setFrameCount == 0)
    }

    @Test func repositionsWhenScreensChange() async {
        let (controller, provider, panel) = make([FakeScreens.mbp14])
        controller.apply(.collapsed)
        controller.start()
        var iterator = panel.frames.makeAsyncIterator()
        _ = await iterator.next()   // initial frame
        provider.screens = [FakeScreens.mbp16]
        provider.fireChange()
        let moved = await iterator.next()
        controller.stop()
        #expect(moved == NotchGeometry.collapsedFrame(for: FakeScreens.mbp16))
    }

    @Test func onlyThePinnedStateIsKeyable() {
        let (controller, _, panel) = make([FakeScreens.mbp14])
        controller.apply(.pinned)
        #expect(panel.keyable)
        controller.apply(.expanded)
        #expect(!panel.keyable)
        controller.apply(.collapsed)
        #expect(!panel.keyable)
    }

    @Test func focusHoldMakesTheExpandedPanelKeyButNeverTheCollapsedOne() {
        let (controller, _, panel) = make([FakeScreens.mbp14])
        controller.apply(.expanded, focusHeld: true)
        #expect(panel.keyable)
        controller.apply(.expanded, focusHeld: false)
        #expect(!panel.keyable)
        controller.apply(.collapsed, focusHeld: true)
        #expect(!panel.keyable)
    }

    @Test func reportsTheNotchKindOnFirstPlacementAndWhenItChanges() {
        let (controller, _, _) = make([FakeScreens.mbp14])
        var kinds: [NotchKind] = []
        controller.onKindChange = { kinds.append($0) }
        controller.apply(.collapsed)
        controller.apply(.expanded)
        #expect(kinds.count == 1)
        controller.setOverride(.noNotch)
        #expect(kinds.last == NotchKind.none && kinds.count == 2)
    }
}
