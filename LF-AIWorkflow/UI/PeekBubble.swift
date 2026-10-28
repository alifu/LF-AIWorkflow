//
//  PeekBubble.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Short alert below the menu bar. Hover or click opens the panel on the task.
struct PeekBubble: View {
    let message: PeekMessage
    let pose: MascotPose
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MascotPlaceholder(pose: pose, size: 28)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityLabel("Dismiss alert")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
        .accessibilityHint("Opens the task")
        .accessibilityAddTraits(.isButton)
        .onAppear { AccessibilityNotification.Announcement(message.text).post() }
    }
}

#Preview {
    PeekBubble(message: PeekMessage(taskID: UUID(), text: "Add dark mode: plan ready, approve?", kind: .planReady, sequence: 1),
               pose: .attention, onOpen: {}, onDismiss: {})
        .frame(width: 320, height: 80)
        .padding()
}
