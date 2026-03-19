//
//  ThumbnailCache.swift
//  Jot
//
//  Created by AI on 01.09.25.
//
//  Cache manager for website thumbnails and metadata

import Foundation
import SwiftUI
import Combine
import CryptoKit

@MainActor
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    /// Bounded in-memory metadata cache. Entries are evicted LRU when exceeding maxCacheSize.
    private var metadataCache: [String: WebMetadata] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheSize = 100

    private var loadingUrls: Set<String> = []
    private let metadataFetcher = WebMetadataFetcher()

    private init() {}

    /// Returns a fixed-length SHA256 hex filename for the given URL string.
    private static func thumbnailFilename(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    func getMetadata(for url: String) -> WebMetadata? {
        return metadataCache[url]
    }

    func isLoading(_ url: String) -> Bool {
        return loadingUrls.contains(url)
    }

    func fetchMetadata(for url: String, completion: @escaping (WebMetadata) -> Void) {
        // Return cached if available
        if let cached = metadataCache[url] {
            completion(cached)
            return
        }

        // Prevent duplicate requests
        if loadingUrls.contains(url) {
            return
        }

        loadingUrls.insert(url)

        metadataFetcher.fetchMetadata(from: url) { [weak self] metadata in
            DispatchQueue.main.async {
                self?.insertMetadata(metadata, for: url)
                self?.loadingUrls.remove(url)
                completion(metadata)
            }
        }
    }

    /// Insert metadata with LRU eviction.
    private func insertMetadata(_ metadata: WebMetadata, for url: String) {
        if metadataCache[url] == nil {
            cacheOrder.append(url)
        }
        metadataCache[url] = metadata

        // Evict oldest entries when over limit
        while cacheOrder.count > maxCacheSize {
            let oldest = cacheOrder.removeFirst()
            metadataCache.removeValue(forKey: oldest)
        }
    }

    /// Save thumbnail to disk on a background thread.
    func cacheThumbnail(_ image: NSImage, for url: String) {
        let filename = Self.thumbnailFilename(for: url)
        Task.detached(priority: .utility) {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                return
            }
            let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let thumbnailsDir = documentsPath?.appendingPathComponent("WebClipThumbnails", isDirectory: true)

            if let thumbnailsDir = thumbnailsDir {
                try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
                let filePath = thumbnailsDir.appendingPathComponent(filename)
                try? jpegData.write(to: filePath)
            }
        }
    }

    /// Load cached thumbnail from disk on a background thread.
    func loadCachedThumbnail(for url: String) async -> NSImage? {
        let filename = Self.thumbnailFilename(for: url)
        return await Task.detached(priority: .utility) {
            let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let thumbnailsDir = documentsPath?.appendingPathComponent("WebClipThumbnails", isDirectory: true)

            if let thumbnailsDir = thumbnailsDir {
                let filePath = thumbnailsDir.appendingPathComponent(filename)
                return NSImage(contentsOf: filePath)
            }

            return nil
        }.value
    }
}
