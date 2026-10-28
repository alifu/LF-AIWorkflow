//
//  StageChipView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// One stage chip: icon, marker and label, so status never depends on color.
struct StageChipView: View {
    let chip: StageChip

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StageStyle.icon(chip.step)).font(.system(size: 9))
            Text(StageStyle.marker(chip.status)).font(.system(size: 9, weight: .bold))
            Text(StageStyle.label(chip.step) + (chip.detail.map { " \($0)" } ?? ""))
                .font(.system(size: 10, weight: chip.status == .active ? .semibold : .regular))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(chip.status == .failed ? Color.red : .clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
    }

    private var foreground: Color {
        switch chip.status {
        case .pending: .secondary
        case .active: .white
        case .done: .primary
        case .failed: .red
        }
    }

    private var background: Color {
        switch chip.status {
        case .active: StageStyle.color(chip.step)
        case .done: .white.opacity(0.14)
        case .pending, .failed: .white.opacity(0.06)
        }
    }
}

struct StageChipStrip: View {
    let chips: [StageChip]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips) { StageChipView(chip: $0) }
        }
    }
}

#Preview {
    StageChipStrip(chips: TaskRowModel(PreviewFixtures.task(state: .fix, fixAttempts: 1), now: PreviewFixtures.epoch).chips)
        .padding()
        .background(.black)
}
