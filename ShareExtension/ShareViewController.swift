//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Moheb Anwari on 20.03.26.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    private var extractedShare: PendingShare?
    private let viewModel = ShareViewModel()

    override func loadView() {
        let hostingView = NSHostingView(
            rootView: ShareExtensionView(
                onSave: { [weak self] title in self?.save(title: title) },
                onCancel: { [weak self] in self?.cancel() },
                viewModel: viewModel
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
        self.view = hostingView

        extractContent()
    }

    // MARK: - Content Extraction

    private func extractContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            markReady(share: nil)
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            // Priority: URL > image > text
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    extractURL(from: attachment)
                    return
                }
            }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    extractImage(from: attachment)
                    return
                }
            }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    extractText(from: attachment)
                    return
                }
            }
        }

        // No matching attachment type found -- enable Save with empty content
        markReady(share: PendingShare(type: .text, title: nil, content: "", imageData: nil, timestamp: Date()))
    }

    private func markReady(share: PendingShare?) {
        extractedShare = share
        viewModel.extractedTitle = share?.title ?? ""
        viewModel.isReady = true
    }

    private func extractURL(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
            let share: PendingShare
            if let url = data as? URL {
                share = PendingShare(
                    type: .url,
                    title: url.host ?? url.absoluteString,
                    content: url.absoluteString,
                    imageData: nil,
                    timestamp: Date()
                )
            } else {
                share = PendingShare(type: .text, title: nil, content: "", imageData: nil, timestamp: Date())
            }
            DispatchQueue.main.async { self?.markReady(share: share) }
        }
    }

    private func extractImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            var imageData: Data?

            if let url = data as? URL {
                imageData = try? Data(contentsOf: url)
            } else if let nsImage = data as? NSImage,
                      let tiff = nsImage.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff) {
                imageData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            }

            guard let raw = imageData else {
                DispatchQueue.main.async {
                    self?.markReady(share: PendingShare(type: .text, title: nil, content: "", imageData: nil, timestamp: Date()))
                }
                return
            }

            // Resize if wider than 1200px
            let resized = Self.resizeImageData(raw, maxWidth: 1200)
            let base64 = resized.base64EncodedString()

            let share = PendingShare(
                type: .image,
                title: nil,
                content: nil,
                imageData: base64,
                timestamp: Date()
            )
            DispatchQueue.main.async { self?.markReady(share: share) }
        }
    }

    private func extractText(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
            let share: PendingShare
            if let text = data as? String {
                let title = String(text.prefix(100)).components(separatedBy: "\n").first ?? "Shared Text"
                share = PendingShare(type: .text, title: title, content: text, imageData: nil, timestamp: Date())
            } else {
                share = PendingShare(type: .text, title: nil, content: "", imageData: nil, timestamp: Date())
            }
            DispatchQueue.main.async { self?.markReady(share: share) }
        }
    }

    // MARK: - Image Resizing

    private static func resizeImageData(_ data: Data, maxWidth: CGFloat) -> Data {
        guard let image = NSImage(data: data) else { return data }
        let size = image.size
        guard size.width > maxWidth else { return data }

        let scale = maxWidth / size.width
        let newSize = NSSize(width: maxWidth, height: size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return data }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? data
    }

    // MARK: - Actions

    private func save(title: String?) {
        guard var share = extractedShare else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        if let title = title, !title.isEmpty {
            share = PendingShare(
                type: share.type,
                title: title,
                content: share.content,
                imageData: share.imageData,
                timestamp: share.timestamp
            )
        }

        do {
            try PendingShareManager.write(share)
        } catch {
            // App Group may be unavailable -- nothing we can do from the extension
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.mohebanwari.Jot.ShareExtension",
                                                          code: 0, userInfo: nil))
    }
}
