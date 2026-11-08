//
//  PanelChrome.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Frame math for the expanded panel's outline and hard shadow (TD-060). The panel shape is inset so that the outline
/// (half its width spills outward) and the shadow's offset land inside the frame instead of being clipped by it.
nonisolated enum PanelChromeGeometry {
    /// Insets from the frame to the panel shape. The top gets the outline's half-width too, so the stroke is never cut.
    /// Complexity: O(1) time, O(1) space
    static func insets(outlineWidth: CGFloat, shadow: ThemeShadow?) -> EdgeInsets {
        let half = max(0, outlineWidth) / 2
        let dx = max(0, shadow?.dx ?? 0)
        let dy = max(0, shadow?.dy ?? 0)
        return EdgeInsets(top: half, leading: half, bottom: half + dy, trailing: half + dx)
    }

    /// The panel shape's rect inside `frame`.
    /// Complexity: O(1) time, O(1) space
    static func shapeRect(in frame: CGRect, outlineWidth: CGFloat, shadow: ThemeShadow?) -> CGRect {
        let insets = insets(outlineWidth: outlineWidth, shadow: shadow)
        return CGRect(x: frame.minX + insets.leading, y: frame.minY + insets.top,
                      width: frame.width - insets.leading - insets.trailing,
                      height: frame.height - insets.top - insets.bottom)
    }
}

/// The panel's paper, hard shadow and outline, drawn in the padded area so nothing is clipped.
struct PanelChrome: View {
    let bottomRadius: CGFloat
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = NotchShape(bottomRadius: bottomRadius)
        let insets = PanelChromeGeometry.insets(outlineWidth: theme.outlineWidth, shadow: theme.shadow)
        ZStack {
            if let shadow = theme.shadow {
                shape.fill(shadow.color.color).offset(x: shadow.dx, y: shadow.dy)
            }
            ThemedBackground().clipShape(shape)
            if theme.outlineWidth > 0 {
                shape.stroke(theme.palette(for: scheme).outline.color, lineWidth: theme.outlineWidth)
            }
        }
        .padding(insets)
    }
}
