//
//  NoteDetailView+Gallery.swift
//  Jot
//
//  Gallery preview and grid logic extracted from NoteDetailView.
//

import SwiftUI

import AppKit

extension NoteDetailView {

    func updateGalleryPreview(for text: String) {
        let filenames = extractGalleryFilenames(from: text)
        let currentIDs = galleryItems.map(\.id)
        let needsReload = filenames != currentIDs

        guard needsReload else {
            // Filenames unchanged — just check if preview needs updating
            updatePreviewFromCurrentItems()
            return
        }

        guard !filenames.isEmpty else {
            galleryItems = []
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

        // Load images off the main thread
        Task.detached(priority: .userInitiated) {
            let loaded = filenames.compactMap { filename -> GalleryGridOverlay.Item? in
                guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename),
                      let image = NSImage(contentsOf: imageURL) else { return nil }
                return GalleryGridOverlay.Item(id: filename, image: image)
            }

            await MainActor.run {
                galleryItems = loaded
                updatePreviewFromCurrentItems()
            }
        }
    }

    private func updatePreviewFromCurrentItems() {
        guard let latestItem = galleryItems.last else {
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

    func loadGalleryImage(named filename: String) -> NSImage? {
        guard let imageURL = ImageStorageManager.shared.getImageURL(for: filename) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
    }
}
