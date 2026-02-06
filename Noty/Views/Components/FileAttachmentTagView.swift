//
//  FileAttachmentTagView.swift
//  Noty
//
//  Capsule tag used to represent non-image file attachments inside the editor.
//

import SwiftUI

struct FileAttachmentTagView: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(FontManager.metadata(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor)
            Text(label.lowercased())
                .font(FontManager.metadata(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 54, minHeight: 20)
        .background(backgroundColor, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.uppercased()) attachment")
    }

    private var iconName: String {
        switch label.lowercased() {
        case "pdf":
            return "doc.richtext"
        case "image":
            return "photo"
        case "audio":
            return "waveform"
        case "video":
            return "play.rectangle"
        default:
            return "doc"
        }
    }

    private var foregroundColor: Color {
        Color("PrimaryTextColor")
    }

    private var backgroundColor: Color {
        Color("SurfaceTranslucentColor")
    }
}
