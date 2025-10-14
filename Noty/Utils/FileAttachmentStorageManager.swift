//
//  FileAttachmentStorageManager.swift
//  Noty
//
//  Persists non-image attachment files dropped into the editor.
//

import Foundation

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

    private let storageDirectoryName = "NotyFiles"

    private init() {
        Task {
            await ensureStorageDirectoryExists()
        }
    }

    public func saveFile(from url: URL) async -> StoredFile? {
        guard let storageURL = await storageDirectoryURL() else {
            NSLog("FileAttachmentStorageManager: Failed to access storage directory")
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
            NSLog(
                "FileAttachmentStorageManager: Stored file %@ as %@",
                originalFilename,
                storedFilename
            )
            return StoredFile(
                storedFilename: storedFilename,
                originalFilename: originalFilename,
                typeIdentifier: typeIdentifier
            )
        } catch {
            NSLog(
                "FileAttachmentStorageManager: Failed to copy %@ -> %@ (%@)",
                url.path,
                destinationURL.path,
                error.localizedDescription
            )
            return nil
        }
    }

    public func fileURL(for storedFilename: String) -> URL? {
        guard let storageURL = try? storageDirectoryURLSync() else {
            return nil
        }
        let fileURL = storageURL.appendingPathComponent(storedFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("FileAttachmentStorageManager: Missing stored file %@", storedFilename)
            return nil
        }
        return fileURL
    }

    public func deleteFile(named storedFilename: String) {
        guard let url = fileURL(for: storedFilename) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            NSLog("FileAttachmentStorageManager: Deleted file %@", storedFilename)
        } catch {
            NSLog(
                "FileAttachmentStorageManager: Failed to delete %@ (%@)",
                storedFilename,
                error.localizedDescription
            )
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
                NSLog("FileAttachmentStorageManager: Created storage directory at %@", url.path)
            } catch {
                NSLog(
                    "FileAttachmentStorageManager: Failed to create directory (%@)",
                    error.localizedDescription
                )
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
