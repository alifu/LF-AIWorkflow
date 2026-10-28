//
//  MascotPlaceholder.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Stand-in for the Phase 6 mascot: an SF Symbol per pose. Decorative, so hidden from VoiceOver.
struct MascotPlaceholder: View {
    let pose: MascotPose
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.7, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch pose {
        case .idle: "face.smiling"
        case .typing: "keyboard"
        case .done: "checkmark.seal.fill"
        case .error: "exclamationmark.triangle.fill"
        case .attention: "bell.badge"
        }
    }
}

#Preview {
    HStack {
        ForEach([MascotPose.idle, .typing, .done, .error, .attention], id: \.self) { MascotPlaceholder(pose: $0, size: 32) }
    }
    .padding()
    .background(.black)
}
