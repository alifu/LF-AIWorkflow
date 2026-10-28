//
//  InboxCapture.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated protocol ResearchInboxAdding: Sendable {
    func add(_ page: CapturedPage) async throws -> InboxResult
}

extension ResearchInbox: ResearchInboxAdding {}

nonisolated struct InboxCaptureOutcome: Sendable, Equatable {
    /// Text for the peek bubble.
    let message: String
    /// Items in the inbox after the capture; nil when nothing was saved or counted.
    let count: Int?
}

/// What the inbox hotkey does: read the current Safari tab and save it to the inbox. Never throws; the
/// outcome always carries a message for the user.
nonisolated struct InboxCapture: Sendable {
    let safari: any SafariControlling
    let inbox: any ResearchInboxAdding

    /// Complexity: O(n) time, O(n) space (n = captured page size)
    func capture() async -> InboxCaptureOutcome {
        do {
            guard let tab = try await safari.currentTab() else {
                return InboxCaptureOutcome(message: "No Safari tab to save", count: nil)
            }
            let page = try await safari.extract(tab)
            if page.hasPasswordField {
                return InboxCaptureOutcome(message: "Not saved: the page has a password field", count: nil)
            }
            switch try await inbox.add(page) {
            case .added(let count): return InboxCaptureOutcome(message: "Saved to inbox (\(count))", count: count)
            case .addedDroppingOldest(let count, _):
                return InboxCaptureOutcome(message: "Saved to inbox (\(count)), oldest dropped", count: count)
            case .duplicate: return InboxCaptureOutcome(message: "Already in the inbox", count: nil)
            }
        } catch let error as SafariError {
            return InboxCaptureOutcome(message: Self.text(for: error), count: nil)
        } catch {
            return InboxCaptureOutcome(message: "Could not save to the inbox", count: nil)
        }
    }

    /// Complexity: O(1) time, O(1) space
    static func text(for error: SafariError) -> String {
        switch error {
        case .automationDenied: "Allow LF-AIWorkflow to control Safari (System Settings > Automation)"
        case .javascriptFromAppleEventsOff: "Turn on Safari > Developer > Allow JavaScript from Apple Events"
        case .safariNotRunning: "Safari is not running"
        case .tabChanged: "The tab changed, try again"
        case .timedOut: "Safari did not answer in time"
        case .outputTooLarge: "The page is too large to save"
        case .malformedOutput: "Could not read the page"
        }
    }
}
