//
//  ImageStorageManager.swift
//  Jot
//
//  Manages image persistence for note attachments.
//  Stores images in Documents/JotImages/ directory with UUID-based filenames.
//

import Foundation
import AppKit
import os

/// Manages local storage and retrieval of images for note attachments
@MainActor
public final class ImageStorageManager {
    
    // Singleton instance for app-wide access
    public static let shared = ImageStorageManager()

    private let logger = Logger(subsystem: "com.jot", category: "ImageStorageManager")

    // Directory name within Documents folder
    private let storageDirectoryName = "JotImages"
    
    // Maximum image width for compression (maintains aspect ratio)
    private let maxImageWidth: CGFloat = 1200
    
    // JPEG compression quality (0.0 to 1.0)
    private let compressionQuality: CGFloat = 0.8
    
    private init() {
        // Ensure storage directory exists on initialization
        Task { [weak self] in
            await self?.ensureStorageDirectoryExists()
        }
    }
    
    // MARK: - Public Methods
    
    /// Save an image from a file URL to the storage directory
    /// - Parameter url: Source URL of the image file
    /// - Returns: Filename of the saved image, or nil if save failed
    public func saveImage(from url: URL) async -> String? {
        // Ensure storage directory exists before writing
        await ensureStorageDirectoryExists()
        guard let storageURL = await getStorageDirectory() else {
            logger.error("Failed to get storage directory")
            return nil
        }

        // Load image from URL
        guard let image = NSImage(contentsOf: url) else {
            logger.error("Failed to load NSImage from URL")
            return nil
        }

        // Resize if needed and compress
        let processedImage = await processImage(image)
        guard let imageData = processedImage else {
            logger.error("Failed to process image")
            return nil
        }

        // Generate unique filename
        let filename = UUID().uuidString + ".jpg"
        let destinationURL = storageURL.appendingPathComponent(filename)

        // Write to disk
        do {
            try imageData.write(to: destinationURL)
            return filename
        } catch {
            logger.error("Failed to write image data: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Save an NSImage directly (e.g. from clipboard paste) to the storage directory
    /// - Parameter image: The NSImage to save
    /// - Returns: Filename of the saved image, or nil if save failed
    public func saveImageData(_ image: NSImage) async -> String? {
        await ensureStorageDirectoryExists()
        guard let storageURL = await getStorageDirectory() else {
            logger.error("Failed to get storage directory")
            return nil
        }

        guard let processedData = await processImage(image) else {
            logger.error("Failed to process clipboard image")
            return nil
        }

        let filename = UUID().uuidString + ".jpg"
        let destinationURL = storageURL.appendingPathComponent(filename)

        do {
            try processedData.write(to: destinationURL)
            return filename
        } catch {
            logger.error("Failed to write clipboard image data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get the full URL for an image filename
    /// - Parameter filename: The image filename
    /// - Returns: Full URL to the image file, or nil if not found
    public func getImageURL(for filename: String) -> URL? {
        guard let storageURL = try? getStorageDirectorySync() else {
            return nil
        }
        let imageURL = storageURL.appendingPathComponent(filename)
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            logger.error("Image file not found: \(filename)")
            return nil
        }
        
        return imageURL
    }
    
    /// Delete an image file
    /// - Parameter filename: The image filename to delete
    public func deleteImage(filename: String) {
        guard let imageURL = getImageURL(for: filename) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: imageURL)
        } catch {
            logger.error("Failed to delete image \(filename): \(error.localizedDescription)")
        }
    }
    
    /// Clean up images that are not referenced in any notes
    /// - Parameter notes: Array of all notes to check for references
    func cleanupUnusedImages(referencedInNotes notes: [Note]) {
        guard let storageURL = try? getStorageDirectorySync() else {
            logger.error("Cannot access storage directory for cleanup")
            return
        }
        
        // Get all image filenames from notes
        var referencedImages = Set<String>()
        // Must exclude both ] and | in capture group to avoid capturing width ratio
        // e.g. [[image|||foo.jpg|||0.3300]] should capture only "foo.jpg"
        let imagePattern = #"\[\[image\|\|\|([^\]|]+)(?:\|\|\|[0-9]*\.?[0-9]+)?\]\]"#

        guard let regex = try? NSRegularExpression(pattern: imagePattern, options: []) else {
            logger.error("Failed to compile image cleanup regex")
            return
        }

        for note in notes {
            let matches = regex.matches(
                in: note.content,
                options: [],
                range: NSRange(note.content.startIndex..., in: note.content)
            )

            for match in matches {
                if let range = Range(match.range(at: 1), in: note.content) {
                    let filename = String(note.content[range])
                    referencedImages.insert(filename)
                }
            }
        }
        
        // Move file enumeration and deletion off the main thread
        let referenced = referencedImages
        let dirURL = storageURL
        let log = logger
        Task.detached(priority: .background) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: dirURL,
                    includingPropertiesForKeys: nil
                )

                for fileURL in fileURLs {
                    let filename = fileURL.lastPathComponent
                    guard !filename.hasPrefix(".") else { continue }
                    if !referenced.contains(filename) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                log.error("Failed to list storage directory: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Ensure the storage directory exists, creating it if necessary
    private func ensureStorageDirectoryExists() async {
        guard let storageURL = await getStorageDirectory() else {
            return
        }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.createDirectory(
                    at: storageURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                logger.error("Failed to create storage directory: \(error.localizedDescription)")
            }
        }
    }
    
    /// Get the storage directory URL
    private func getStorageDirectory() async -> URL? {
        return try? getStorageDirectorySync()
    }
    
    /// Synchronous access to storage directory for callers that cannot await.
    /// Creates the directory if needed.
    func getStorageDirectoryForSync() -> URL? {
        guard let url = try? getStorageDirectorySync() else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Synchronous version of getStorageDirectory
    private static let appGroupID = "group.com.mohebanwari.Jot"

    private func getStorageDirectorySync() throws -> URL {
        let base: URL
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            base = groupURL
        } else {
            base = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
        }
        return base.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }

    /// One-time migration: moves images from the old sandbox Documents/JotImages/
    /// to the App Group container. Idempotent -- skips if already done.
    func migrateFromSandboxIfNeeded() {
        let key = "com.jot.didMigrateFilesToAppGroup.v1.images"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let fm = FileManager.default
        guard let oldBase = try? fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        let oldDir = oldBase.appendingPathComponent(storageDirectoryName, isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        guard let groupURL = fm.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return
        }
        let newDir = groupURL.appendingPathComponent(storageDirectoryName, isDirectory: true)

        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)

        guard let files = try? fm.contentsOfDirectory(
            at: oldDir, includingPropertiesForKeys: nil) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        for file in files {
            let dest = newDir.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try fm.moveItem(at: file, to: dest)
                } catch {
                    logger.error("migrateFromSandbox: failed to move \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }
    
    /// Process image: resize if needed and compress to JPEG.
    /// Captures a CGImage snapshot on the main actor (AppKit-safe), then
    /// runs all heavy work (resize, compress) on a detached background task.
    private func processImage(_ image: NSImage) async -> Data? {
        // Capture CGImage on @MainActor before entering the background task —
        // NSImage is not thread-safe; cgImage(forProposedRect:) calls AppKit internally
        guard let sourceCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let maxWidth = maxImageWidth
        let quality = compressionQuality
        let width = CGFloat(sourceCG.width)
        let height = CGFloat(sourceCG.height)

        return await Task.detached(priority: .userInitiated) {
            // Calculate new size if image is too large
            var targetCG: CGImage = sourceCG
            if width > maxWidth {
                let scale = maxWidth / width
                let newSize = NSSize(width: maxWidth, height: height * scale)
                let bitsPerComponent = 8
                let bytesPerRow = Int(newSize.width) * 4
                guard let colorSpace = sourceCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(
                          data: nil,
                          width: Int(newSize.width),
                          height: Int(newSize.height),
                          bitsPerComponent: bitsPerComponent,
                          bytesPerRow: bytesPerRow,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else {
                    return nil
                }
                ctx.interpolationQuality = .high
                ctx.draw(sourceCG, in: CGRect(origin: .zero, size: newSize))
                guard let resized = ctx.makeImage() else { return nil }
                targetCG = resized
            }

            // Convert CGImage to JPEG via NSBitmapImageRep (thread-safe when
            // constructed directly from a CGImage, not from NSImage)
            let bitmapRep = NSBitmapImageRep(cgImage: targetCG)
            guard let jpegData = bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ) else {
                return nil
            }

            return jpegData
        }.value
    }
}

