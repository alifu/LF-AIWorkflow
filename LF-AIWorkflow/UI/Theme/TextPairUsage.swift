//
//  TextPairUsage.swift
//  LF-AIWorkflow
//

import SwiftUI

/// A palette token a view draws as text or as a stroke.
nonisolated enum TextToken: String, Sendable, CaseIterable {
    case primaryText, secondaryText, emphasizedText, dismissText, accent, warning, failure, caution, success

    /// Complexity: O(1) time, O(1) space
    func color(in palette: ThemePalette) -> ThemeColor {
        switch self {
        case .primaryText: palette.primaryText
        case .secondaryText: palette.secondaryText
        case .emphasizedText: palette.emphasizedText
        case .dismissText: palette.dismissText
        case .accent: palette.accent
        case .warning: palette.warning
        case .failure: palette.failure
        case .caution: palette.caution
        case .success: palette.success
        }
    }
}

/// A background a view draws text on. Translucent ones are composited over what is under them.
nonisolated enum TextSurface: String, Sendable, CaseIterable {
    case panel, row, attentionRow, chip, chipDone, field, sheet, fieldOnSheet
    case warningSubtleTint, warningPill, successPill
    case failureBadge, warningBadge, cautionBadge, accentBadge, neutralBadge

    /// Complexity: O(1) time, O(1) space
    func color(in theme: AppTheme, scheme: ColorScheme) -> ThemeColor {
        let palette = theme.palette(for: scheme)
        let panel = palette.panelBackground
        let row = palette.rowBackground.composited(over: panel)
        switch self {
        case .panel: return panel
        case .row: return row
        case .attentionRow: return palette.attentionRowBackground.composited(over: panel)
        case .chip: return palette.chipBackground.composited(over: panel)
        case .chipDone: return palette.chipDoneBackground.composited(over: panel)
        case .field: return palette.fieldBackground.composited(over: panel)
        case .sheet: return palette.sheetBackground.composited(over: panel)
        case .fieldOnSheet: return palette.fieldBackground.composited(over: palette.sheetBackground.composited(over: panel))
        case .warningSubtleTint: return palette.warning.fading(theme.subtleTintOpacity).composited(over: panel)
        case .warningPill: return palette.warning.fading(theme.pillTintOpacity).composited(over: row)
        case .successPill: return palette.success.fading(theme.pillTintOpacity).composited(over: row)
        case .failureBadge: return palette.failure.fading(theme.badgeTintOpacity).composited(over: row)
        case .warningBadge: return palette.warning.fading(theme.badgeTintOpacity).composited(over: row)
        case .cautionBadge: return palette.caution.fading(theme.badgeTintOpacity).composited(over: row)
        case .accentBadge: return palette.accent.fading(theme.badgeTintOpacity).composited(over: row)
        case .neutralBadge: return palette.neutral.fading(theme.badgeTintOpacity).composited(over: row)
        }
    }
}

/// One (token, surface) combination that some view draws. `AppTheme.allTextPairs` derives the contrast sweep from this list,
/// and a test checks that every palette token the views use as `foregroundStyle` appears in it.
nonisolated struct TextPairUsage: Sendable, Equatable {
    let text: TextToken
    let surface: TextSurface

    var name: String { "\(text.rawValue) on \(surface.rawValue)" }

    private static let bodySurfaces: [TextSurface] = [.panel, .row, .attentionRow, .chip, .chipDone, .field, .sheet, .fieldOnSheet]

    /// Primary and secondary text sit on every surface; the rest on the places the views put them.
    static let all: [TextPairUsage] =
        [TextToken.primaryText, .secondaryText].flatMap { text in bodySurfaces.map { TextPairUsage(text: text, surface: $0) } }
        + [
            // Peek bubble (panel fill), error/notice lines, and cards that carry warnings or errors.
            TextPairUsage(text: .emphasizedText, surface: .panel),
            TextPairUsage(text: .dismissText, surface: .panel),
            TextPairUsage(text: .accent, surface: .panel),
            TextPairUsage(text: .failure, surface: .panel),
            TextPairUsage(text: .warning, surface: .panel),
            TextPairUsage(text: .caution, surface: .panel),
            TextPairUsage(text: .success, surface: .panel),
            TextPairUsage(text: .warning, surface: .row),
            TextPairUsage(text: .warning, surface: .attentionRow),
            TextPairUsage(text: .warning, surface: .sheet),
            TextPairUsage(text: .accent, surface: .row),
            TextPairUsage(text: .warning, surface: .warningSubtleTint),
            // Plan pill and review severity badges; their label is the system primary color, approximated by primaryText.
            TextPairUsage(text: .primaryText, surface: .warningPill),
            TextPairUsage(text: .primaryText, surface: .successPill),
            TextPairUsage(text: .primaryText, surface: .failureBadge),
            TextPairUsage(text: .primaryText, surface: .warningBadge),
            TextPairUsage(text: .primaryText, surface: .cautionBadge),
            TextPairUsage(text: .primaryText, surface: .accentBadge),
            TextPairUsage(text: .primaryText, surface: .neutralBadge),
        ]
}
