//
//  ArtStylePicker.swift
//  LF-AIWorkflow
//
//  In UI/Theme/ because it lists the art styles; the General tab only places it.

import SwiftUI

/// Segmented choice between the art styles. The preview beside it shows both looks, so the choice needs no toggling.
struct ArtStylePicker: View {
    @Binding var selection: ArtStyle

    var body: some View {
        Picker("Art style", selection: $selection) {
            ForEach(ArtStyle.allCases, id: \.self) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Art style")
        .accessibilityValue(selection.title)
        .accessibilityHint("Changes the look of the notch panel and Settings")
    }
}

#Preview {
    @Previewable @State var style: ArtStyle = .popArt
    ArtStylePicker(selection: $style)
        .padding()
        .frame(width: 360)
}
