//
//  ImageAttachmentTagView.swift
//  Jot
//
//  Capsule tag used to represent inline image attachments inside the editor.
//

import SwiftUI

struct ImageAttachmentTagView: View {
    let label: String

    @Environment(\.colorScheme) private var colorScheme

    init(label: String = "image") {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 4) {
            Image("gallery")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(foregroundColor)
            Text(label)
                .font(FontManager.metadata(size: 11, weight: .medium))
                .foregroundStyle(foregroundColor)
                .textCase(.lowercase)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: 54, minHeight: 20)
        .background(backgroundColor, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) attachment")
    }

    private var foregroundColor: Color {
        Color("PrimaryTextColor")
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.09)
    }
}
