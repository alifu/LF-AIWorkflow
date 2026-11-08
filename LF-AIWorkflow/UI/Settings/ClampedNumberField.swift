//
//  ClampedNumberField.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Whole-number field. Commits on Return or when focus leaves; out-of-range input is clamped and the reason is shown.
struct ClampedNumberField: View {
    let label: String
    let range: ClosedRange<Int>
    let value: Int
    var isEnabled = true
    var accessibilityLabel: String?
    let onCommit: (Int) -> Void

    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        LabeledContent {
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .disabled(!isEnabled)
                .accessibilityLabel(accessibilityLabel ?? label)
                .accessibilityHint("Enter a whole number from \(range.lowerBound) to \(range.upperBound)")
        } label: {
            Text(label)
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in text = String(newValue) }
        if let message {
            Text(message)
                .font(theme.captionFont.font)
                .foregroundStyle(palette.primaryText.color)
                .accessibilityLabel("\(label): \(message)")
        }
    }

    /// Complexity: O(n) time, O(1) space (n = text length)
    private func commit() {
        switch SettingsValidation.parse(text, range: range, label: label) {
        case .value(let number, let note):
            message = note
            text = String(number)
            if number != value { onCommit(number) }
        case .invalid(let reason):
            message = reason
        }
    }
}

#Preview {
    @Previewable @State var stored = 150_000
    Form {
        ClampedNumberField(label: "Per-task budget", range: SettingsLimits.taskTokens, value: stored) { stored = $0 }
    }
    .padding()
    .frame(width: 420)
}
