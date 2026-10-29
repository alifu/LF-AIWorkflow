//
//  HoverController.swift
//  LF-AIWorkflow
//

import Observation

/// Debounced panel state machine. Pure logic: no AppKit, time comes from the injected clock.
/// At most one hover task (expand or collapse) and one peek task are pending at any time.
@Observable
final class HoverController {
    private(set) var state: NotchPanelState = .collapsed
    /// True while the composer or a sheet has typing focus (the panel then must not collapse and may become key).
    private(set) var isFocusHeld = false

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let expandDelay: Duration
    @ObservationIgnored private let collapseDelay: Duration
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var pointerInside = false

    init(clock: any Clock<Duration> = ContinuousClock(), expandDelay: Duration = .milliseconds(120),
         collapseDelay: Duration = .milliseconds(300)) {
        self.clock = clock
        self.expandDelay = expandDelay
        self.collapseDelay = collapseDelay
    }

    // MARK: - Pointer

    /// Complexity: O(1) time, O(1) space
    func pointerEntered() {
        pointerInside = true
        cancelHover()
        switch state {
        case .peek:
            cancelPeek()
            state = .expanded
        case .collapsed:
            hoverTask = schedule(after: expandDelay) { controller in
                guard controller.pointerInside, controller.state == .collapsed else { return }
                controller.state = .expanded
            }
        case .expanded, .pinned:
            break
        }
    }

    /// Complexity: O(1) time, O(1) space
    func pointerExited() {
        pointerInside = false
        cancelHover()
        scheduleCollapse()
    }

    // MARK: - Holds

    /// Pinned stays open regardless of the pointer. Unpinning returns to expanded (and collapses if the pointer is away).
    func setPinned(_ isPinned: Bool) {
        if isPinned {
            cancelHover()
            cancelPeek()
            state = .pinned
        } else if state == .pinned {
            state = .expanded
            if !pointerInside { scheduleCollapse() }
        }
    }

    /// Composer or sheet focus acts like a pin without changing the state.
    func setFocusHold(_ isHeld: Bool) {
        isFocusHeld = isHeld
        if isHeld {
            if state == .expanded { cancelHover() }
        } else if !pointerInside {
            scheduleCollapse()
        }
    }

    // MARK: - Peek

    /// Shows the peek bubble from the collapsed state only; never overrides expanded or pinned.
    func showPeek(for duration: Duration = .seconds(7), enabled: Bool = true) {
        guard enabled, state == .collapsed, !pointerInside else { return }
        cancelPeek()
        state = .peek
        peekTask = schedule(after: duration) { controller in
            guard controller.state == .peek else { return }
            controller.state = .collapsed
        }
    }

    func dismissPeek() {
        guard state == .peek else { return }
        cancelPeek()
        state = .collapsed
    }

    // MARK: - Keyboard / VoiceOver

    /// Opens the panel without a pointer (keyboard, VoiceOver, peek activation). Never sets `pointerInside`, so the
    /// panel can still auto-collapse after the pointer later enters and leaves or once focus is released.
    /// Complexity: O(1) time, O(1) space
    func expand() {
        cancelHover()
        cancelPeek()
        if state == .collapsed || state == .peek { state = .expanded }
    }

    // MARK: - Dismissal (Esc, click outside)

    /// Closes an expanded panel. Pinned stays open; focus hold does not block (an explicit close).
    /// Complexity: O(1) time, O(1) space
    func collapse() {
        cancelHover()
        guard state == .expanded else { return }
        state = .collapsed
    }

    /// Esc: dismisses a peek, collapses an expanded panel, never touches a pinned one. Ignored while an IME composition is active
    /// (Esc then cancels the composition). Returns true when the key was used.
    /// Complexity: O(1) time, O(1) space
    @discardableResult
    func escapePressed(isComposingText: Bool) -> Bool {
        guard !isComposingText else { return false }
        switch state {
        case .peek:
            dismissPeek()
            return true
        case .expanded:
            collapse()
            return true
        case .collapsed, .pinned:
            return false
        }
    }

    /// A click outside the panel: collapses unless pinned or a composer/sheet holds focus.
    /// Complexity: O(1) time, O(1) space
    func clickedOutside() {
        guard !isFocusHeld else { return }
        collapse()
    }

    // MARK: - Hotkey

    func toggleFromHotkey() {
        cancelHover()
        cancelPeek()
        switch state {
        case .collapsed, .peek: state = .expanded
        case .expanded, .pinned: state = .collapsed
        }
    }

    // MARK: - Scheduling

    /// Replaces any pending hover task, so at most one collapse is ever waiting.
    /// Complexity: O(1) time, O(1) space
    private func scheduleCollapse() {
        guard state == .expanded, !isFocusHeld else { return }
        cancelHover()
        hoverTask = schedule(after: collapseDelay) { controller in
            guard !controller.pointerInside, !controller.isFocusHeld, controller.state == .expanded else { return }
            controller.state = .collapsed
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping (HoverController) -> Void) -> Task<Void, Never> {
        let clock = clock
        return Task { [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }
}
