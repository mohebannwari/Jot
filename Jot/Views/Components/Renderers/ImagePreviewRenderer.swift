//
//  ImagePreviewRenderer.swift
//  Jot
//
//  Renders an image file preview inline in the note editor.
//

import SwiftUI

struct ImagePreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if loadFailed {
                placeholder("Unable to load image")
            } else if let image {
                let ar = image.size.width / max(image.size.height, 1)
                let height = containerWidth / max(ar, 0.01)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: containerWidth, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                placeholder("Loading image...")
            }
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color("SurfaceElevatedColor"))
            .frame(maxWidth: containerWidth)
            .frame(height: 200)
            .overlay {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - Loading

    private func loadImage() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        guard let loaded = NSImage(contentsOf: url), loaded.isValid else {
            loadFailed = true
            return
        }

        image = loaded
    }
}
