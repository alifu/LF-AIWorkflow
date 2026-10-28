//
//  MascotView.swift
//  LF-AIWorkflow
//

import SwiftUI

nonisolated enum MouthShape: Sendable, Hashable {
    case smile, grin, flat, open
}

/// What the mascot draws at one instant. A pure value, so the pose rules are testable without pixels.
nonisolated struct MascotFrame: Sendable, Hashable {
    let eyesClosed: Bool
    /// Vertical offset as a fraction of the view size (positive is down).
    let bob: CGFloat
    let mouth: MouthShape
    let sweat: Bool
    let alert: Bool

    /// Idle blinks once per period; the eyes are closed for the first `blinkDuration` seconds of each period.
    static let blinkPeriod: TimeInterval = 4
    static let blinkDuration: TimeInterval = 0.15
    /// Typing bobs at this many cycles per second.
    static let bobFrequency: Double = 2
    /// Bob amplitude as a fraction of the view size.
    static let bobAmplitude: CGFloat = 0.04

    /// Reduce Motion gives the same static frame at every time: no blink and no bob.
    /// Complexity: O(1) time, O(1) space
    static func frame(for pose: MascotPose, at time: TimeInterval, reduceMotion: Bool) -> MascotFrame {
        let animated = !reduceMotion
        return MascotFrame(
            eyesClosed: animated && isIdle(pose) && isBlinking(at: time),
            bob: animated && isTyping(pose) ? bobOffset(at: time) : 0,
            mouth: mouth(for: pose),
            sweat: isError(pose),
            alert: isAttention(pose))
    }

    /// Complexity: O(1) time, O(1) space
    private static func isBlinking(at time: TimeInterval) -> Bool {
        time.truncatingRemainder(dividingBy: blinkPeriod) < blinkDuration
    }

    /// Complexity: O(1) time, O(1) space
    private static func bobOffset(at time: TimeInterval) -> CGFloat {
        bobAmplitude * CGFloat(sin(2 * Double.pi * bobFrequency * time))
    }

    /// Switch matching avoids the main-actor `Equatable` conformance, so this stays callable from any context.
    /// Complexity: O(1) time, O(1) space
    private static func mouth(for pose: MascotPose) -> MouthShape {
        switch pose {
        case .idle: .smile
        case .typing: .open
        case .done: .grin
        case .error: .flat
        case .attention: .open
        }
    }

    private static func isIdle(_ pose: MascotPose) -> Bool {
        if case .idle = pose { true } else { false }
    }

    private static func isTyping(_ pose: MascotPose) -> Bool {
        if case .typing = pose { true } else { false }
    }

    private static func isError(_ pose: MascotPose) -> Bool {
        if case .error = pose { true } else { false }
    }

    private static func isAttention(_ pose: MascotPose) -> Bool {
        if case .attention = pose { true } else { false }
    }
}

extension MascotPose {
    /// VoiceOver description of the pose.
    nonisolated var accessibilityLabel: String {
        switch self {
        case .idle: "Idle"
        case .typing: "Working"
        case .done: "Done"
        case .error: "Error"
        case .attention: "Needs attention"
        }
    }
}

/// The notch mascot. Animates with a timeline (15 fps) and freezes under Reduce Motion.
struct MascotView: View {
    let pose: MascotPose
    var size: CGFloat = 24

    static let frameInterval: TimeInterval = 1.0 / 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        let look = MascotLook(style: theme.mascotStyle, colors: theme.mascot,
                              outlineWidth: theme.outlineWidth, size: size)
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: reduceMotion)) { context in
            let frame = MascotFrame.frame(
                for: pose, at: context.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
            Canvas { canvas, canvasSize in
                MascotShapes.draw(frame, in: &canvas, size: canvasSize, look: look)
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pose.accessibilityLabel)
    }
}

/// Every pose at the two sizes the app uses (24 pt in the bar and bubbles, 64 pt in task detail).
private struct MascotPreviewRow: View {
    let pose: MascotPose
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 16) {
            MascotView(pose: pose, size: 24)
            MascotView(pose: pose, size: 64)
        }
        .padding()
        .background(theme.palette(for: scheme).panelBackground.color)
    }
}

#Preview("Idle") { MascotPreviewRow(pose: .idle) }
#Preview("Typing") { MascotPreviewRow(pose: .typing) }
#Preview("Done") { MascotPreviewRow(pose: .done) }
#Preview("Error") { MascotPreviewRow(pose: .error) }
#Preview("Attention") { MascotPreviewRow(pose: .attention) }

/// How the mascot is drawn in the active theme. Built from `MascotStyle` and the outline token, so views never branch on a theme.
nonisolated struct MascotLook: Sendable, Equatable {
    let colors: MascotColors
    /// Outline width as a fraction of the side (0 = no outline).
    let outline: CGFloat
    let showsCheeks: Bool

    /// Complexity: O(1) time, O(1) space
    init(style: MascotStyle, colors: MascotColors, outlineWidth: CGFloat, size: CGFloat) {
        self.colors = colors
        self.outline = style == .outlined && size > 0 ? outlineWidth / size : 0
        self.showsCheeks = style == .outlined
    }
}
