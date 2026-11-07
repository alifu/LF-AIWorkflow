//
//  HoverControllerTests.swift
//  LF-AIWorkflowTests
//

import Testing
@testable import LF_AIWorkflow

@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)))
struct HoverControllerTests {
    private func make() -> (HoverController, ManualClock) {
        let clock = ManualClock()
        return (HoverController(clock: clock), clock)
    }

    /// Lets the sleeper register, moves time, and waits for the woken task to finish.
    private func elapse(_ controller: HoverController, _ clock: ManualClock, _ duration: Duration) async {
        await clock.waitForSleepers(1)
        clock.advance(by: duration)
        await controller.settle()
    }

    // MARK: expand reason (TD-065)

    @Test func timerExpandIsHoverWhileExpandHotkeyAndPinAreExplicit() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        #expect(c.state == .expanded)
        #expect(c.expandReason == .hover)
        c.expand()
        #expect(c.expandReason == .explicit)
        c.collapse()
        c.toggleFromHotkey()
        #expect(c.expandReason == .explicit)
    }

    // MARK: expand

    @Test func expandsAfter120msNotBefore() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(119))
        #expect(c.state == .collapsed)
        await elapse(c, clock, .milliseconds(1))
        #expect(c.state == .expanded)
    }

    @Test func exitBeforeExpandDelayCancelsExpand() async {
        let (c, clock) = make()
        c.pointerEntered()
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(100))
        c.pointerExited()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(100))   // 200 ms since the first enter, 100 since the second
        #expect(c.state == .collapsed)
        await elapse(c, clock, .milliseconds(20))
        #expect(c.state == .expanded)
    }

    @Test func exitWithoutReenterNeverExpands() async {
        let (c, clock) = make()
        c.pointerEntered()
        await clock.waitForSleepers(1)
        c.pointerExited()
        await c.settle()
        clock.advance(by: .seconds(5))
        await c.settle()
        #expect(c.state == .collapsed)
    }

    // MARK: collapse

    @Test func collapsesAfter300msOfExit() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.pointerExited()
        await elapse(c, clock, .milliseconds(299))
        #expect(c.state == .expanded)
        await elapse(c, clock, .milliseconds(1))
        #expect(c.state == .collapsed)
    }

    @Test func reenterAt299msCancelsCollapse() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.pointerExited()
        await elapse(c, clock, .milliseconds(299))
        c.pointerEntered()
        await c.settle()
        clock.advance(by: .seconds(5))
        await c.settle()
        #expect(c.state == .expanded)
    }

    @Test func pinnedNeverCollapses() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.setPinned(true)
        #expect(c.state == .pinned)
        c.pointerExited()
        await c.settle()
        clock.advance(by: .seconds(5))
        await c.settle()
        #expect(c.state == .pinned)
    }

    @Test func unpinningWhilePointerIsOutsideCollapses() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.setPinned(true)
        c.pointerExited()
        c.setPinned(false)
        #expect(c.state == .expanded)
        await elapse(c, clock, .milliseconds(300))
        #expect(c.state == .collapsed)
    }

    @Test func focusHoldBlocksCollapseThenReleaseCollapses() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.setFocusHold(true)
        c.pointerExited()
        await c.settle()
        clock.advance(by: .seconds(5))
        await c.settle()
        #expect(c.state == .expanded)
        c.setFocusHold(false)
        await elapse(c, clock, .milliseconds(300))
        #expect(c.state == .collapsed)
    }

    @Test func focusHoldAppliedWhileCollapseIsPendingCancelsIt() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.pointerExited()
        await clock.waitForSleepers(1)
        c.setFocusHold(true)
        await c.settle()
        clock.advance(by: .seconds(5))
        await c.settle()
        #expect(c.state == .expanded)
    }

    // MARK: peek

    @Test func peekAutoDismissesAfterTimeout() async {
        let (c, clock) = make()
        c.showPeek(for: .seconds(7))
        #expect(c.state == .peek)
        await elapse(c, clock, .seconds(6))
        #expect(c.state == .peek)
        await elapse(c, clock, .seconds(1))
        #expect(c.state == .collapsed)
    }

    @Test func peekNeverOverridesExpandedOrPinned() async {
        let (c, clock) = make()
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.showPeek()
        #expect(c.state == .expanded)
        c.setPinned(true)
        c.showPeek()
        #expect(c.state == .pinned)
    }

    @Test func hoveringThePeekOpensExpandedAndStopsTheTimeout() async {
        let (c, clock) = make()
        c.showPeek(for: .seconds(7))
        await clock.waitForSleepers(1)
        c.pointerEntered()
        #expect(c.state == .expanded)
        await c.settle()
        clock.advance(by: .seconds(10))
        await c.settle()
        #expect(c.state == .expanded)
    }

    @Test func dismissPeekCollapsesAndIgnoresOtherStates() async {
        let (c, clock) = make()
        c.showPeek()
        c.dismissPeek()
        #expect(c.state == .collapsed)
        c.pointerEntered()
        await elapse(c, clock, .milliseconds(120))
        c.dismissPeek()
        #expect(c.state == .expanded)
    }

    // MARK: hotkey

    @Test func hotkeyTogglesOpenAndClosed() async {
        let (c, _) = make()
        c.toggleFromHotkey()
        #expect(c.state == .expanded)
        c.toggleFromHotkey()
        #expect(c.state == .collapsed)
    }

    @Test func hotkeyOpensFromPeekAndClosesPinned() async {
        let (c, _) = make()
        c.showPeek()
        c.toggleFromHotkey()
        #expect(c.state == .expanded)
        c.setPinned(true)
        c.toggleFromHotkey()
        #expect(c.state == .collapsed)
    }

    // MARK: pending task hygiene

    @Test func rapidEnterExitLeavesExactlyOnePendingTask() async {
        let (c, clock) = make()
        for _ in 0..<100 {
            c.pointerEntered()
            c.pointerExited()
        }
        c.pointerEntered()
        await clock.waitForSleepers(1)
        await Task.yield()
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(120))
        await c.settle()
        #expect(c.state == .expanded)
    }

    @Test func schedulingACollapseCancelsThePriorOne() async {
        let (c, clock) = make()
        c.expand()
        c.pointerExited()
        await clock.waitForSleepers(1)
        c.setFocusHold(false)                       // pointer is away, so a second collapse is scheduled
        await c.settle()
        #expect(clock.sleeperCount == 1)
    }

    // MARK: keyboard / VoiceOver open

    @Test func expandOpensWithoutAPointerSoItCollapsesOnceFocusIsReleased() async {
        let (c, clock) = make()
        c.expand()
        #expect(c.state == .expanded)
        c.setFocusHold(true)
        c.setFocusHold(false)
        await elapse(c, clock, .milliseconds(300))
        #expect(c.state == .collapsed)
    }

    @Test func expandLeavesPinnedAndCancelsPeek() {
        let (c, _) = make()
        c.setPinned(true)
        c.expand()
        #expect(c.state == .pinned)
        let (d, _) = make()
        d.showPeek()
        d.expand()
        #expect(d.state == .expanded)
    }
}

// MARK: - Esc, click outside, peek setting (Phase 6 step 12, TD-054, TD-005)

@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)))
struct HoverDismissalTests {
    @Test func keyboardExpandCanBeCollapsedWithEsc() {
        let c = HoverController()
        c.expand()
        #expect(c.state == .expanded)
        #expect(c.escapePressed(isComposingText: false))
        #expect(c.state == .collapsed)
    }

    @Test func escWhileComposingIMETextLeavesThePanelOpen() {
        let c = HoverController()
        c.expand()
        #expect(!c.escapePressed(isComposingText: true))
        #expect(c.state == .expanded)
    }

    @Test func escDoesNotCloseAPinnedPanel() {
        let c = HoverController()
        c.expand()
        c.setPinned(true)
        #expect(!c.escapePressed(isComposingText: false))
        #expect(c.state == .pinned)
    }

    @Test func escClosesEvenWhenTheComposerHoldsFocus() {
        let c = HoverController()
        c.expand()
        c.setFocusHold(true)
        #expect(c.escapePressed(isComposingText: false))
        #expect(c.state == .collapsed)
    }

    @Test func escDismissesAPeek() {
        let c = HoverController()
        c.showPeek()
        #expect(c.escapePressed(isComposingText: false))
        #expect(c.state == .collapsed)
    }

    @Test func escWhenCollapsedIsNotHandled() {
        let c = HoverController()
        #expect(!c.escapePressed(isComposingText: false))
    }

    @Test func clickOutsideCollapsesAnExpandedPanel() {
        let c = HoverController()
        c.expand()
        c.clickedOutside()
        #expect(c.state == .collapsed)
    }

    @Test func clickOutsideIsIgnoredWhenPinned() {
        let c = HoverController()
        c.expand()
        c.setPinned(true)
        c.clickedOutside()
        #expect(c.state == .pinned)
    }

    @Test func clickOutsideIsIgnoredWhileFocusIsHeld() {
        let c = HoverController()
        c.expand()
        c.setFocusHold(true)
        c.clickedOutside()
        #expect(c.state == .expanded)
    }

    @Test func collapseCancelsAPendingHoverExpand() async {
        let clock = ManualClock()
        let c = HoverController(clock: clock)
        c.pointerEntered()
        await clock.waitForSleepers(1)
        c.collapse()
        clock.advance(by: .milliseconds(200))
        await c.settle()
        #expect(c.state == .collapsed)
    }

    @Test func peekDisabledNeverShowsTheBubble() {
        let c = HoverController()
        c.showPeek(enabled: false)
        #expect(c.state == .collapsed)
        c.showPeek(enabled: true)
        #expect(c.state == .peek)
    }
}

/// Test aid: lets tasks that were just woken by the clock run to completion (main-actor FIFO).
@MainActor
extension HoverController {
    func settle() async {
        for _ in 0..<3 { await Task.yield() }
    }
}
