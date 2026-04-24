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
            Image("IconFileLink")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)

            Text(label)
                .jotUI(FontManager.uiLabel5(weight: .regular))
                .lineLimit(1)

            Image("IconArrowRightUpCircle")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
        // Match NoteMetadataSection attachment pills: primary button tokens only (no app tint).
        .foregroundColor(Color("ButtonPrimaryTextColor"))
        .padding(.horizontal, FontManager.InlineEditorPillRasterPadding.horizontal)
        .padding(.vertical, FontManager.InlineEditorPillRasterPadding.vertical)
        .background(Color("ButtonPrimaryBgColor"), in: Capsule())
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.uppercased()) attachment")
    }
}
