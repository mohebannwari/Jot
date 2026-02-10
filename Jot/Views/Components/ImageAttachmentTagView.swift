//
//  ImageAttachmentTagView.swift
//  Jot
//
//  Capsule tag used to represent inline image attachments inside the editor.
//

import SwiftUI

struct ImageAttachmentTagView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image("insert link")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(foregroundColor)
            Text("image")
                .font(FontManager.metadata(size: 12, weight: .medium))
                .foregroundStyle(foregroundColor)
                .textCase(.lowercase)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: 54, minHeight: 20)
        .background(backgroundColor, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image attachment")
    }

    private var foregroundColor: Color {
        Color("PrimaryTextColor")
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color("SurfaceTranslucentColor")
    }
}
