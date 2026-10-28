//
//  ScreenProvider.swift
//  LF-AIWorkflow
//

import AppKit

protocol ScreenProviding {
    var screens: [ScreenMetrics] { get }
    /// Fires when displays are added, removed or rearranged.
    var changes: AsyncStream<Void> { get }
}

/// Real displays, via `NSScreen` and `didChangeScreenParametersNotification`.
struct SystemScreenProvider: ScreenProviding {
    var screens: [ScreenMetrics] { NSScreen.screens.map(ScreenMetrics.init) }

    var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didChangeScreenParametersNotification).map({ _ in () }) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
