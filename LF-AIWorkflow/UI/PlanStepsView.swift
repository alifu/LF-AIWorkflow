//
//  PlanStepsView.swift
//  LF-AIWorkflow
//

import SwiftUI

/// Numbered, read-only plan steps. Each row reads as "Step 2 of 5, ...".
struct PlanStepsView: View {
    let steps: [String]
    var maxHeight: CGFloat = 130

    var body: some View {
        if steps.isEmpty {
            Text("No numbered steps found in this plan.").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(index + 1) of \(steps.count), \(step)")
                    }
                }
            }
            .frame(maxHeight: maxHeight)
            .accessibilityLabel("Plan steps")
        }
    }
}

#if DEBUG
#Preview {
    PlanStepsView(steps: ["Add the model", "Wire the view", "Write tests"])
        .padding().frame(width: 420).background(.black).environment(\.colorScheme, .dark)
}
#endif
