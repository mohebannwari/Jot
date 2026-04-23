//
//  PDFPreviewRenderer.swift
//  Jot
//
//  Renders a multi-page PDF preview inline in the note editor.
//  Medium mode: 1 page visible + peek. Full mode: 2 pages visible + peek.
//

import SwiftUI
import PDFKit

struct PDFPreviewRenderer: View {
    let storedFilename: String
    let containerWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var pageImages: [NSImage] = []
    @State private var loadFailed = false

    private let peekAmount: CGFloat = 24
    private let pageGap: CGFloat = 8
    private let pageCornerRadius: CGFloat = 10 // concentric: glass 22 - padding 12

    private var isFull: Bool { containerWidth > 500 }

    private var pageWidth: CGFloat {
        if isFull {
            return (containerWidth - 2 * pageGap - peekAmount) / 2
        } else {
            return containerWidth - pageGap - peekAmount
        }
    }

    private var pageHeight: CGFloat {
        guard let first = pageImages.first else { return 400 }
        let ar = first.size.width / max(first.size.height, 1)
        return pageWidth / max(ar, 0.01)
    }

    var body: some View {
        Group {
            if loadFailed {
                placeholder("Unable to load PDF")
            } else if pageImages.isEmpty {
                placeholder("Loading PDF...")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: pageGap) {
                        ForEach(Array(pageImages.enumerated()), id: \.offset) { _, image in
                            pageCard(for: image)
                        }
                    }
                }
                .frame(height: pageHeight)
            }
        }
        .task {
            await loadPages()
        }
    }

    // MARK: - Subviews

    private func pageCard(for image: NSImage) -> some View {
        let ar = image.size.width / max(image.size.height, 1)
        let h = pageWidth / max(ar, 0.01)
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pageWidth, height: h)
            .clipShape(RoundedRectangle(cornerRadius: pageCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        RoundedRectangle(cornerRadius: pageCornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color("DetailPaneColor") : Color.white)
            .frame(height: 400)
            .overlay {
                Text(message)
                    .jotUI(FontManager.uiLabel5(weight: .medium))
                    .foregroundStyle(Color("SecondaryTextColor"))
            }
    }

    // MARK: - Loading

    /// Maximum number of pages to pre-render as thumbnails.
    /// Only the first batch is loaded; the preview scroll shows enough to convey content.
    private static let maxPrerenderedPages = 3

    private func loadPages() async {
        guard let url = FileAttachmentStorageManager.shared.fileURL(for: storedFilename) else {
            loadFailed = true
            return
        }

        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            loadFailed = true
            return
        }

        let pageLimit = min(document.pageCount, Self.maxPrerenderedPages)
        var images: [NSImage] = []
        images.reserveCapacity(pageLimit)

        for index in 0..<pageLimit {
            guard let page = document.page(at: index) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let baseScale = pageWidth / max(pageRect.width, 1)
            let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
            let thumbnailSize = CGSize(
                width: pageRect.width * baseScale * screenScale,
                height: pageRect.height * baseScale * screenScale
            )

            let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            images.append(thumbnail)
        }

        if images.isEmpty {
            loadFailed = true
        } else {
            pageImages = images
        }
    }
}
