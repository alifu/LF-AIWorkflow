//
//  ClickOutsideMonitor.swift
//  LF-AIWorkflow
//

import AppKit

/// Reports mouse clicks that land outside this app's windows while it is running (global monitor; needs no permission
/// for mouse events). Started when the panel opens, stopped when it closes.
final class ClickOutsideMonitor {
    private var token: Any?
    var isRunning: Bool { token != nil }

    /// Complexity: O(1) time, O(1) space
    func start(onClick: @escaping () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in onClick() }
        }
    }

    /// Complexity: O(1) time, O(1) space
    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    isolated deinit { stop() }
}
