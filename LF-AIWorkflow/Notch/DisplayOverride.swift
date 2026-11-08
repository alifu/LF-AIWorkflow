//
//  DisplayOverride.swift
//  LF-AIWorkflow
//

import CoreGraphics

/// Debug aid: pretend the menu-bar screen has or lacks a notch.
nonisolated enum DisplayOverride: String, Sendable, CaseIterable {
    case auto, notch, noNotch

    static let defaultsKey = "displayOverride"
    static let launchArgument = "-LFSimulateNotch"
    static let simulatedNotchWidth: CGFloat = 184
    static let simulatedNotchHeight: CGFloat = 32

    /// Returns metrics as the override would present the screen.
    /// Complexity: O(1) time, O(1) space
    func apply(to m: ScreenMetrics) -> ScreenMetrics {
        switch self {
        case .auto: return m
        case .noNotch:
            guard m.safeAreaTopInset > 0 else { return m }
            return ScreenMetrics(frame: m.frame, safeAreaTopInset: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil,
                                 menuBarHeight: max(m.menuBarHeight, m.safeAreaTopInset))
        case .notch:
            guard m.safeAreaTopInset == 0 else { return m }
            let inset = Self.simulatedNotchHeight
            let side = max(0, (m.frame.width - Self.simulatedNotchWidth) / 2)
            return ScreenMetrics(
                frame: m.frame, safeAreaTopInset: inset,
                auxiliaryTopLeft: CGRect(x: m.frame.minX, y: m.frame.maxY - inset, width: side, height: inset),
                auxiliaryTopRight: CGRect(x: m.frame.maxX - side, y: m.frame.maxY - inset, width: side, height: inset),
                menuBarHeight: max(m.menuBarHeight, inset))
        }
    }

    /// `-LFSimulateNotch YES|NO` wins over the stored value; anything unrecognised falls through.
    /// Complexity: O(n) time, O(1) space
    static func resolve(arguments: [String], stored: String?) -> DisplayOverride {
        if let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) {
            switch arguments[index + 1].uppercased() {
            case "YES", "TRUE", "1": return .notch
            case "NO", "FALSE", "0": return .noNotch
            default: break
            }
        }
        return stored.flatMap(DisplayOverride.init(rawValue:)) ?? .auto
    }
}
