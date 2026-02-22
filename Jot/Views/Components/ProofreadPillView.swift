//
//  ProofreadPillView.swift
//  Jot
//
//  Liquid glass pill for inline proofread suggestions.
//  Rendered as NSHostingView inside the text editor view hierarchy.
//

import SwiftUI

struct ProofreadPillView: View {
    let replacement: String
    let maxWidth: CGFloat
    let onAccept: () -> Void

    var body: some View {
        Button(action: onAccept) {
            Text(replacement)
                .font(FontManager.body(size: 16, weight: .regular))
                .foregroundColor(Color("PrimaryTextColor"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .buttonStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .macPointingHandCursor()
        .subtleHoverScale(1.04)
    }
}
