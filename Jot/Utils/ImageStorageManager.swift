//
//  ImageStorageManager.swift
//  Jot
//
//  Manages image persistence for note attachments.
//  Stores images in Documents/JotImages/ directory with UUID-based filenames.
//

import Foundation
import AppKit

/// Manages local storage and retrieval of images for note attachments
@MainActor
public final class ImageStorageManager {
    
    // Singleton instance for app-wide access
    public static let shared = ImageStorageManager()
    
    // Directory name within Documents folder
    private let storageDirectoryName = "JotImages"
    
    // Maximum image width for compression (maintains aspect ratio)
    private let maxImageWidth: CGFloat = 1200
    
    // JPEG compression quality (0.0 to 1.0)
    private let compressionQuality: CGFloat = 0.8
    
    private init() {
        // Ensure storage directory exists on initialization
        Task {
            await ensureStorageDirectoryExists()
        }
    }
    
    // MARK: - Public Methods
    
    /// Save an image from a file URL to the storage directory
    /// - Parameter url: Source URL of the image file
    /// - Returns: Filename of the saved image, or nil if save failed
    public func saveImage(from url: URL) async -> String? {
        NSLog("ImageStorageManager: Attempting to save image from URL: %@", url.path)
        
        // Ensure storage directory exists
        guard let storageURL = await getStorageDirectory() else {
            NSLog("ImageStorageManager: Failed to get storage directory")
            return nil
        }
        
        // Load image from URL
        guard let image = NSImage(contentsOf: url) else {
            NSLog("ImageStorageManager: Failed to load NSImage from URL")
            return nil
        }
        
        // Resize if needed and compress
        let processedImage = await processImage(image)
        guard let imageData = processedImage else {
            NSLog("ImageStorageManager: Failed to process image")
            return nil
        }
        
        // Generate unique filename
        let filename = UUID().uuidString + ".jpg"
        let destinationURL = storageURL.appendingPathComponent(filename)
        
        // Write to disk
        do {
            try imageData.write(to: destinationURL)
            NSLog("ImageStorageManager: Successfully saved image as %@", filename)
            return filename
        } catch {
            NSLog("ImageStorageManager: Failed to write image data: %@", error.localizedDescription)
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
            NSLog("ImageStorageManager: Image file not found: %@", filename)
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
            NSLog("ImageStorageManager: Deleted image: %@", filename)
        } catch {
            NSLog("ImageStorageManager: Failed to delete image %@: %@", filename, error.localizedDescription)
        }
    }
    
    /// Clean up images that are not referenced in any notes
    /// - Parameter notes: Array of all notes to check for references
    func cleanupUnusedImages(referencedInNotes notes: [Note]) {
        NSLog("ImageStorageManager: Starting cleanup of unused images")
        
        guard let storageURL = try? getStorageDirectorySync() else {
            NSLog("ImageStorageManager: Cannot access storage directory for cleanup")
            return
        }
        
        // Get all image filenames from notes
        var referencedImages = Set<String>()
        let imagePattern = #"\[\[image\|\|\|([^\]]+)\]\]"#
        
        for note in notes {
            if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
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
        }
        
        NSLog("ImageStorageManager: Found %d referenced images", referencedImages.count)
        
        // Get all files in storage directory
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: storageURL,
                includingPropertiesForKeys: nil
            )
            
            var deletedCount = 0
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                
                // Skip hidden files
                guard !filename.hasPrefix(".") else { continue }
                
                // Delete if not referenced
                if !referencedImages.contains(filename) {
                    try? FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                    NSLog("ImageStorageManager: Cleaned up unreferenced image: %@", filename)
                }
            }
            
            NSLog("ImageStorageManager: Cleanup complete. Deleted %d orphaned images", deletedCount)
        } catch {
            NSLog("ImageStorageManager: Failed to list storage directory: %@", error.localizedDescription)
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
                NSLog("ImageStorageManager: Created storage directory at %@", storageURL.path)
            } catch {
                NSLog("ImageStorageManager: Failed to create storage directory: %@", error.localizedDescription)
            }
        }
    }
    
    /// Get the storage directory URL
    private func getStorageDirectory() async -> URL? {
        return try? getStorageDirectorySync()
    }
    
    /// Synchronous version of getStorageDirectory
    private func getStorageDirectorySync() throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsURL.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }
    
    /// Process image: resize if needed and compress to JPEG
    private func processImage(_ image: NSImage) async -> Data? {
        // Get image dimensions
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Calculate new size if image is too large
        var newSize = NSSize(width: width, height: height)
        if width > maxImageWidth {
            let scale = maxImageWidth / width
            newSize = NSSize(width: maxImageWidth, height: height * scale)
        }

        // Resize if needed
        let resizedImage: NSImage
        if newSize != NSSize(width: width, height: height) {
            resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            image.draw(
                in: NSRect(origin: .zero, size: newSize),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            resizedImage.unlockFocus()
        } else {
            resizedImage = image
        }

        // Convert to JPEG data
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionQuality]
              ) else {
            return nil
        }

        return jpegData
    }
}

