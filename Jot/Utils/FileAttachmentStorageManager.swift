//
//  FileAttachmentStorageManager.swift
//  Jot
//
//  Persists non-image attachment files dropped into the editor.
//

import Foundation
import ImageIO
import os
import PDFKit

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@MainActor
public final class FileAttachmentStorageManager {
    public struct StoredFile {
        public let storedFilename: String
        public let originalFilename: String
        public let typeIdentifier: String
    }

    public static let shared = FileAttachmentStorageManager()

    private let logger = Logger(subsystem: "com.jot", category: "FileAttachmentStorageManager")
    private let storageDirectoryName = "JotFiles"

    private init() {
        Task {
            await ensureStorageDirectoryExists()
        }
    }

    public func saveFile(from url: URL) async -> StoredFile? {
        guard let storageURL = await storageDirectoryURL() else {
            logger.error("saveFile: Failed to access storage directory")
            return nil
        }

        let fileManager = FileManager.default
        let originalFilename = url.lastPathComponent
        let ext = url.pathExtension
        let typeIdentifier = resolveTypeIdentifier(for: url, fallbackExtension: ext)

        let uniqueComponent = UUID().uuidString
        let sanitizedExtension = ext.isEmpty ? "" : ".\(ext.lowercased())"
        let storedFilename = uniqueComponent + sanitizedExtension
        let destinationURL = storageURL.appendingPathComponent(storedFilename, isDirectory: false)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            return StoredFile(
                storedFilename: storedFilename,
                originalFilename: originalFilename,
                typeIdentifier: typeIdentifier
            )
        } catch {
            logger.error("saveFile: Failed to copy \(url.path) -> \(destinationURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    public func fileURL(for storedFilename: String) -> URL? {
        guard let storageURL = try? storageDirectoryURLSync() else {
            return nil
        }
        let fileURL = storageURL.appendingPathComponent(storedFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("fileURL: Missing stored file \(storedFilename)")
            return nil
        }
        return fileURL
    }

    /// Returns width/height aspect ratio of the first PDF page.
    static func pdfPageAspectRatio(for storedFilename: String) -> CGFloat? {
        guard let url = shared.fileURL(for: storedFilename) else { return nil }
        guard let doc = PDFDocument(url: url),
              let page = doc.page(at: 0) else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        return box.width / box.height
    }

    /// Returns width/height aspect ratio by reading image headers only (no full decode).
    static func imageAspectRatio(for storedFilename: String) -> CGFloat? {
        guard let url = shared.fileURL(for: storedFilename) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        return w / h
    }

    public func deleteFile(named storedFilename: String) {
        guard let url = fileURL(for: storedFilename) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("deleteFile: Failed to delete \(storedFilename): \(error.localizedDescription)")
        }
    }

    /// Clean up file attachments that are not referenced in any notes.
    /// - Parameter notes: All notes (active + archived + deleted) to check for references
    func cleanupUnusedFiles(referencedInNotes notes: [Note]) {
        guard let storageURL = try? storageDirectoryURLSync() else {
            logger.error("cleanupUnusedFiles: Cannot access storage directory")
            return
        }

        // Collect all referenced stored filenames from [[file|typeId|storedName|origName]] tags
        var referencedFiles = Set<String>()
        // Pattern captures the storedFilename (second pipe-delimited field)
        let filePattern = #"\[\[file\|[^|]+\|([^|]+)\|[^\]]*\]\]"#
        guard let regex = try? NSRegularExpression(pattern: filePattern, options: []) else {
            logger.error("cleanupUnusedFiles: Failed to compile regex")
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
                    referencedFiles.insert(String(note.content[range]))
                }
            }
        }

        // Move file I/O off the main thread
        let referenced = referencedFiles
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
                log.error("cleanupUnusedFiles: Failed to list directory: \(error.localizedDescription)")
            }
        }
    }

    private func resolveTypeIdentifier(for url: URL, fallbackExtension ext: String) -> String {
        if let values = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
           let identifier = values.typeIdentifier {
            return identifier
        }

        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, iOS 14.0, *) {
            if let type = UTType(filenameExtension: ext) {
                return type.identifier
            }
        }
        #endif

        if !ext.isEmpty {
            return "public.data.\(ext.lowercased())"
        }
        return "public.data"
    }

    private func ensureStorageDirectoryExists() async {
        guard let url = await storageDirectoryURL() else { return }
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            do {
                try manager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                logger.error("ensureStorageDirectoryExists: Failed to create directory: \(error.localizedDescription)")
            }
        }
    }

    private func storageDirectoryURL() async -> URL? {
        return try? storageDirectoryURLSync()
    }

    private func storageDirectoryURLSync() throws -> URL {
        let manager = FileManager.default
        let documentsURL = try manager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documentsURL.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }
}
