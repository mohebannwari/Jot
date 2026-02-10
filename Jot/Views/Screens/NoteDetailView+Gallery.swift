//
//  NoteDetailView+Gallery.swift
//  Jot
//
//  Gallery preview and grid logic extracted from NoteDetailView.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NoteDetailView {

    func updateGalleryPreview(for text: String) {
        let filenames = extractGalleryFilenames(from: text)
        let currentIDs = galleryItems.map(\.id)
        let needsReload = filenames != currentIDs

        let items: [GalleryGridOverlay.Item]
        if needsReload {
            items = filenames.compactMap { filename -> GalleryGridOverlay.Item? in
                guard let loadedImage = loadGalleryImage(named: filename) else { return nil }
                return GalleryGridOverlay.Item(id: filename, image: loadedImage)
            }
            galleryItems = items
        } else {
            items = galleryItems
        }

        guard let latestItem = items.last else {
            lastGalleryFilename = nil
            if galleryPreviewImage != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    galleryPreviewImage = nil
                }
            }
            if showGalleryGrid {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showGalleryGrid = false
                }
            }
            return
        }

        let shouldUpdatePreview = latestItem.id != lastGalleryFilename || galleryPreviewImage == nil
        lastGalleryFilename = latestItem.id

        guard shouldUpdatePreview else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            galleryPreviewImage = latestItem.image
        }
    }

    func extractGalleryFilenames(from text: String) -> [String] {
        guard let regex = Self.imageTagRegex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[range])
        }
    }

    func loadGalleryImage(named filename: String) -> PlatformImage? {
        guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
            return nil
        }

        #if os(macOS)
        return NSImage(contentsOf: imageURL)
        #else
        return UIImage(contentsOfFile: imageURL.path)
        #endif
    }
}
