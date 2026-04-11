//
//  ThumbnailPreviewRenderer.swift
//  Jot
//
//  Renders a QuickLook-generated thumbnail for arbitrary file types inline in the note editor.
//  Matches PDF-style card: fixed A4 aspect height, thumbnail fills width (aspect fill) and clips.
//

import SwiftUI
import QuickLookThumbnailing

struct ThumbnailPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnail: NSImage?
    @State private var loadFailed = false

    // A4 page ratio (width/height) used as the default height reservation
    // before the actual thumbnail dimensions are known.
    static let defaultDocumentAspectRatio: CGFloat = 1 / 1.41421356237

    static func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        width / defaultDocumentAspectRatio
    }

    private var previewHeight: CGFloat {
        Self.preferredHeight(forWidth: containerWidth)
    }

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
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: containerWidth, height: previewHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
    }

    private var fallbackIcon: some View {
        let icon = fileTypeIcon
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
            .frame(height: previewHeight)
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
            .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
            .frame(height: previewHeight)
            .overlay {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - File Info

    private var displayFilename: String {
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

        let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Request an explicit large pixel size with scale=1.0 so Quick Look
        // cannot cap the output at a low thumbnail resolution. Some QL
        // generators ignore the scale parameter, so baking the pixels into
        // the size guarantees enough data for sharp Retina display.
        let pixelWidth: CGFloat = max(containerWidth * displayScale, 2048)
        let pixelHeight = pixelWidth / Self.defaultDocumentAspectRatio
        let size = CGSize(width: pixelWidth, height: pixelHeight)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 1.0,
            representationTypes: .all
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let cgImage = representation.cgImage

            // Set logical size so SwiftUI treats the bitmap as Retina-backed.
            // The image will be downscaled to containerWidth, which is always
            // sharp (unlike upscaling, which causes blur).
            let logicalW = CGFloat(cgImage.width) / displayScale
            let logicalH = CGFloat(cgImage.height) / displayScale
            let image = NSImage(cgImage: cgImage, size: NSSize(width: logicalW, height: logicalH))
            thumbnail = image
        } catch {
            loadFailed = true
        }
    }
}
