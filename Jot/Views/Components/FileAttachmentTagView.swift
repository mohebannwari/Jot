//
//  FileAttachmentTagView.swift
//  Jot
//
//  Capsule tag used to represent non-image file attachments inside the editor.
//

import SwiftUI

struct FileAttachmentTagView: View {
    let label: String

    private var assetIconName: String? {
        switch label.lowercased() {
        case "image": return "gallery"
        default: return nil
        }
    }

    private var systemIconName: String {
        switch label.lowercased() {
        case "pdf": return "doc.richtext"
        case "audio": return "waveform"
        case "video": return "play.rectangle"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let assetName = assetIconName {
                    Image(assetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: systemIconName)
                        .font(FontManager.icon(weight: .medium))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(width: 20, height: 20)

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

    private var foregroundColor: Color {
        Color("PrimaryTextColor")
    }

    private var backgroundColor: Color {
        Color("SurfaceTranslucentColor")
    }
}
