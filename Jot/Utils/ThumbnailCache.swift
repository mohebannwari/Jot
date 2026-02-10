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

@MainActor
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    
    private var metadataCache: [String: WebMetadata] = [:]
    private var loadingUrls: Set<String> = []
    private let metadataFetcher = WebMetadataFetcher()
    
    private init() {}
    
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
                self?.metadataCache[url] = metadata
                self?.loadingUrls.remove(url)
                completion(metadata)
            }
        }
    }
    
    func cacheThumbnail(_ image: NSImage, for url: String) {
        // Save thumbnail to disk for persistence
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            
            let filename = url.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "default"
            let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let thumbnailsDir = documentsPath?.appendingPathComponent("WebClipThumbnails", isDirectory: true)
            
            // Create thumbnails directory if it doesn't exist
            if let thumbnailsDir = thumbnailsDir {
                try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
                let filePath = thumbnailsDir.appendingPathComponent("\(filename).jpg")
                try? jpegData.write(to: filePath)
            }
        }
    }
    
    func loadCachedThumbnail(for url: String) -> NSImage? {
        let filename = url.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "default"
        let documentsPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let thumbnailsDir = documentsPath?.appendingPathComponent("WebClipThumbnails", isDirectory: true)
        
        if let thumbnailsDir = thumbnailsDir {
            let filePath = thumbnailsDir.appendingPathComponent("\(filename).jpg")
            return NSImage(contentsOf: filePath)
        }
        
        return nil
    }
}
