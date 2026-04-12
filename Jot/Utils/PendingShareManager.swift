//
//  PendingShareManager.swift
//  Jot
//
//  Shared between the main app target and the Share Extension.
//  Uses App Group container to pass data via JSON files.
//

import Foundation

/// Shared between main app and Share Extension -- must be nonisolated for cross-process use.
nonisolated struct PendingShare: Codable, Sendable {
    nonisolated enum ShareType: String, Codable, Sendable {
        case url
        case text
        case image
    }

    let type: ShareType
    let title: String?
    let content: String?
    let imageData: String? // base64
    let timestamp: Date
}

nonisolated enum PendingShareManager {

    private static let appGroupID = "group.com.mohebanwari.Jot"
    private static let directoryName = "PendingShares"

    private static var pendingDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Write a pending share from the Share Extension.
    static func write(_ share: PendingShare) throws {
        guard let directory = pendingDirectory else {
            throw PendingShareError.appGroupUnavailable
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).json"
        let fileURL = directory.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(share)
        // Second line of defense if the extension ever writes an oversized payload.
        guard data.count <= 48 * 1024 * 1024 else {
            throw PendingShareError.payloadTooLarge
        }
        try data.write(to: fileURL, options: .atomic)
    }

    /// Consume all pending shares from the main app. Deletes each file after reading.
    static func consumeAll() -> [PendingShare] {
        guard let directory = pendingDirectory else { return [] }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        var shares: [PendingShare] = []
        let decoder = JSONDecoder()

        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let share = try? decoder.decode(PendingShare.self, from: data) else {
                // Malformed file -- remove it so it doesn't block future reads
                try? fileManager.removeItem(at: file)
                continue
            }
            shares.append(share)
            try? fileManager.removeItem(at: file)
        }

        return shares.sorted { $0.timestamp < $1.timestamp }
    }
}

nonisolated enum PendingShareError: LocalizedError {
    case appGroupUnavailable
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group container is not available. Ensure the App Group entitlement is configured."
        case .payloadTooLarge:
            return "Shared content is too large to save."
        }
    }
}
