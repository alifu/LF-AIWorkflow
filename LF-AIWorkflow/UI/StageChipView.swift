//
//  StageChipView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The done or failed celebration in flight: which status, so the burst picks the right fill and word.
struct StageCelebration: Equatable {
    let status: StageChip.Status
}

/// One stage chip: icon, marker and label, so status never depends on color.
struct StageChipView: View {
    let chip: StageChip
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebration: StageCelebration?

    /// Complexity: O(1) time, O(1) space
    var body: some View {
        let palette = theme.palette(for: scheme)
        HStack(spacing: 3) {
            Image(systemName: StageStyle.icon(chip.step)).font(theme.iconFont.font)
            Text(StageStyle.marker(chip.status)).font(theme.iconFont.weighted(.bold).font)
            Text(StageStyle.label(chip.step) + (chip.detail.map { " \($0)" } ?? ""))
                .font((chip.status == .active ? theme.chipFont.weighted(.semibold) : theme.chipFont).font)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(foreground(palette))
        .background(Capsule().fill(background(palette)))
        .overlay { border(palette) }
        .overlay { celebrationBadge(palette) }
        .animation(CelebrationPolicy.animation(reduceMotion: reduceMotion), value: celebration)
        .onChange(of: chip.status) { _, status in
            celebration = CelebrationPolicy.label(for: status) == nil ? nil : StageCelebration(status: status)
        }
        .task(id: celebration) {
            guard celebration != nil else { return }
            try? await Task.sleep(for: CelebrationPolicy.duration)
            guard !Task.isCancelled else { return }
            celebration = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
    }

    /// Complexity: O(1) time, O(1) space
    private func foreground(_ palette: ThemePalette) -> Color {
        switch chip.status {
        case .pending: palette.secondaryText.color
        case .active: palette.onStageFill.color
        case .done: palette.primaryText.color
        case .failed: theme.statusFills == .solid ? palette.onStageFill.color : palette.failure.color
        }
    }

    /// Complexity: O(1) time, O(1) space
    private func background(_ palette: ThemePalette) -> Color {
        switch chip.status {
        case .active: theme.stageColor(chip.step, for: scheme).color
        case .done: palette.chipDoneBackground.color
        case .pending: palette.chipBackground.color
        case .failed: theme.statusFills == .solid ? palette.failedFill.color : palette.chipBackground.color
        }
    }

    /// Solid themes outline every chip; tinted themes only ring a failed chip.
    /// Complexity: O(1) time, O(1) space
    @ViewBuilder private func border(_ palette: ThemePalette) -> some View {
        if theme.statusFills == .solid {
            Capsule().strokeBorder(palette.outline.color, lineWidth: theme.outlineWidth)
        } else if chip.status == .failed {
            Capsule().strokeBorder(palette.failure.color, lineWidth: 1)
        }
    }

    /// Comic burst behind the word for 1.2 s. Only the burst theme shows it; the fade theme keeps the checkmark alone.
    /// Complexity: O(1) time, O(1) space
    @ViewBuilder private func celebrationBadge(_ palette: ThemePalette) -> some View {
        if theme.celebration == .burst, let celebration, let word = CelebrationPolicy.label(for: celebration.status) {
            ZStack {
                BurstShape().fill((celebration.status == .failed ? palette.failedFill : palette.burstFill).color)
                Text(word).font(theme.chipFont.font).foregroundStyle(palette.onStageFill.color)
            }
            .frame(width: Self.burstSide, height: Self.burstSide)
            .transition(.scale)
            .accessibilityHidden(true)
        }
    }

    /// Side of the square the burst is drawn in (points).
    static let burstSide: CGFloat = 44
}

struct StageChipStrip: View {
    let chips: [StageChip]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips) { StageChipView(chip: $0) }
        }
    }
}

#Preview("Pop Art active") {
    StageChipStrip(chips: TaskRowModel(PreviewFixtures.task(state: .fix, fixAttempts: 1), now: PreviewFixtures.epoch).chips)
        .padding()
        .background(.black)
        .environment(\.appTheme, .popArt)
}

#Preview("Classic active") {
    StageChipStrip(chips: TaskRowModel(PreviewFixtures.task(state: .fix, fixAttempts: 1), now: PreviewFixtures.epoch).chips)
        .padding()
        .background(.black)
        .environment(\.appTheme, .classic)
}
