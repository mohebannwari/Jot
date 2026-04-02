//
//  FileAttachmentTagView.swift
//  Jot
//
//  Capsule tag used to represent non-image file attachments inside the editor.
//

import SwiftUI

struct FileAttachmentTagView: View {
    let label: String

    @Environment(\.colorScheme) private var colorScheme

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
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.2)
                .lineLimit(1)

            Image("IconArrowRightUpCircle")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
        .foregroundColor(Color("PrimaryTextColor"))
        .padding(4)
        .background(Color("BlockContainerColor"), in: Capsule())
        .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.uppercased()) attachment")
    }
}
