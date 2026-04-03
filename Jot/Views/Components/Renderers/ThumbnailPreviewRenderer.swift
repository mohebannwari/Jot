//
//  ThumbnailPreviewRenderer.swift
//  Jot
//
//  Renders a QuickLook-generated thumbnail for arbitrary file types inline in the note editor.
//

import SwiftUI
import QuickLookThumbnailing

struct ThumbnailPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @State private var thumbnail: NSImage?
    @State private var loadFailed = false

    private let contentHeight: CGFloat = 200

    var body: some View {
        Group {
            if loadFailed {
                fallbackIcon
            } else if let thumbnail {
                thumbnailCard(image: thumbnail)
            } else {
                placeholder("Loading preview...")
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Subviews

    private func thumbnailCard(image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: containerWidth, maxHeight: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
    }

    private var fallbackIcon: some View {
        let icon = fileTypeIcon
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color("SurfaceElevatedColor"))
            .frame(height: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                    Text(displayFilename)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color("SecondaryTextColor"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color("SurfaceElevatedColor"))
            .frame(height: contentHeight)
            .overlay {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - File Info

    private var displayFilename: String {
        // Strip the UUID prefix to show a readable name
        let ext = (storedFilename as NSString).pathExtension
        return ext.isEmpty ? storedFilename : "file.\(ext)"
    }

    private var fileTypeIcon: NSImage {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            return NSWorkspace.shared.icon(for: .data)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = CGSize(width: containerWidth, height: contentHeight)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.nsImage
        } catch {
            loadFailed = true
        }
    }
}
