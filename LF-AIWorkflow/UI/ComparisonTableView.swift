//
//  ComparisonTableView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// The parsed comparison table as a grid of plain text (never raw markdown).
struct ComparisonTableView: View {
    let table: ComparisonTable
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: ThemePalette { theme.palette(for: scheme) }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(theme.emphasisFont.font)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(theme.bodyFont.font).foregroundStyle(palette.primaryText.color)
                        }
                    }
                }
            }
            .padding(8)
        }
        .themedSurface(.field)
        .accessibilityLabel("Comparison table, \(table.rows.count) rows")
    }
}
