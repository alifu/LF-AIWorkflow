//
//  ThemedSurface.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Draws a surface role with the theme's fill, corner, outline and shadow. Views name a role; they never style it.
/// Complexity: O(1) time, O(1) space
struct ThemedSurface: ViewModifier {
    let role: SurfaceRole
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius(for: role), style: .continuous)
        content
            .background { fill(shape) }
            .overlay {
                if theme.outlineWidth > 0 {
                    shape.strokeBorder(theme.palette(for: scheme).outline.color, lineWidth: theme.outlineWidth)
                }
            }
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
        let painted = shape.fill(theme.fill(for: role, scheme: scheme).color)
        if let shadow = theme.shadow {
            painted.shadow(color: shadow.color.color, radius: shadow.blur, x: shadow.dx, y: shadow.dy)
        } else {
            painted
        }
    }
}

extension View {
    /// Fill, corner, outline and shadow of a surface role from the active theme.
    /// Complexity: O(1) time, O(1) space
    func themedSurface(_ role: SurfaceRole) -> some View {
        modifier(ThemedSurface(role: role))
    }
}
