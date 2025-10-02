import Foundation
import SwiftData
import OSLog
import Combine

/// Comprehensive data backup and persistence management for Noty app
@MainActor
final class DataBackupManager: ObservableObject {

    // MARK: - Singleton
    static let shared = DataBackupManager()

    // MARK: - Published Properties
    @Published private(set) var backupStatus: BackupStatus = .idle
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var backupSize: Int64 = 0
    @Published private(set) var autoBackupEnabled: Bool = true

    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.noty.app", category: "DataBackup")
    private let performanceMonitor = PerformanceMonitor.shared
    private var backupTimer: Timer?
    private let fileManager = FileManager.default

    // MARK: - Configuration
    private let backupInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private let maxBackupVersions = 7 // Keep 7 days of backups
    private let compressionEnabled = true

    // MARK: - Backup Locations
    private var backupDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let notySupport = appSupport.appendingPathComponent("Noty")
        let backupsDir = notySupport.appendingPathComponent("Backups")

        // Ensure directory exists
        try? fileManager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        return backupsDir
    }

    private var swiftDataStoreURL: URL? {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let notySupport = appSupport.appendingPathComponent("Noty")
        let storeURL = notySupport.appendingPathComponent("default.store")
        return fileManager.fileExists(atPath: storeURL.path) ? storeURL : nil
    }

    private init() {
        loadBackupSettings()
        setupAutoBackup()
    }

    // MARK: - Public Methods

    /// Perform manual backup with progress tracking
    func performBackup() async -> BackupResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .backup,
            recordCount: 0
        ) {
            await _performBackup()
        }
    }

    /// Restore from a specific backup
    func restoreBackup(from backupURL: URL) async -> RestoreResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .restore,
            recordCount: 0
        ) {
            await _restoreBackup(from: backupURL)
        }
    }

    /// Get list of available backups
    func getAvailableBackups() -> [BackupMetadata] {
        do {
            let backupFiles = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])

            return backupFiles
                .filter { $0.pathExtension == "notybackup" }
                .compactMap { createBackupMetadata(from: $0) }
                .sorted { $0.creationDate > $1.creationDate }
        } catch {
            logger.error("Failed to get available backups: \(error.localizedDescription)")
            return []
        }
    }

    /// Export data for sharing or external backup
    func exportData(format: ExportFormat) async -> ExportResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .export,
            recordCount: 0
        ) {
            await _exportData(format: format)
        }
    }

    /// Import data from external source
    func importData(from url: URL, format: ExportFormat) async -> ImportResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .dataImport,
            recordCount: 0
        ) {
            await _importData(from: url, format: format)
        }
    }

    /// Clean up old backups based on retention policy
    func cleanupOldBackups() {
        let backups = getAvailableBackups()
        let backupsToDelete = backups.dropFirst(maxBackupVersions)

        for backup in backupsToDelete {
            do {
                try fileManager.removeItem(at: backup.url)
                logger.info("Deleted old backup: \(backup.url.lastPathComponent)")
            } catch {
                logger.error("Failed to delete backup \(backup.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Toggle auto backup
    func setAutoBackupEnabled(_ enabled: Bool) {
        autoBackupEnabled = enabled
        saveBackupSettings()

        if enabled {
            setupAutoBackup()
        } else {
            backupTimer?.invalidate()
            backupTimer = nil
        }

        logger.info("Auto backup \(enabled ? "enabled" : "disabled")")
    }

    /// Get backup statistics
    func getBackupStatistics() -> BackupStatistics {
        let backups = getAvailableBackups()
        let totalSize = backups.reduce(0) { $0 + $1.fileSize }

        return BackupStatistics(
            totalBackups: backups.count,
            totalSize: totalSize,
            oldestBackup: backups.last?.creationDate,
            newestBackup: backups.first?.creationDate,
            lastBackupDate: lastBackupDate
        )
    }
}

// MARK: - Private Implementation

private extension DataBackupManager {

    func _performBackup() async -> BackupResult {
        guard let storeURL = swiftDataStoreURL else {
            logger.error("SwiftData store not found")
            return BackupResult(success: false, error: .storeNotFound, backupURL: nil)
        }

        backupStatus = .inProgress

        do {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let backupFileName = "noty_backup_\(timestamp).notybackup"
            let backupURL = backupDirectory.appendingPathComponent(backupFileName)

            // Create backup bundle
            let bundleURL = backupURL.appendingPathExtension("bundle")
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

            // Copy SwiftData store
            let storeBackupURL = bundleURL.appendingPathComponent("store.sqlite")
            try fileManager.copyItem(at: storeURL, to: storeBackupURL)

            // Copy related files (WAL, SHM)
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")

            if fileManager.fileExists(atPath: walURL.path) {
                try fileManager.copyItem(at: walURL, to: bundleURL.appendingPathComponent("store.sqlite-wal"))
            }

            if fileManager.fileExists(atPath: shmURL.path) {
                try fileManager.copyItem(at: shmURL, to: bundleURL.appendingPathComponent("store.sqlite-shm"))
            }

            // Create metadata
            let metadata = BackupMetadata(
                version: "1.0",
                creationDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                noteCount: 0, // Will be populated from actual count
                url: backupURL,
                fileSize: 0 // Will be calculated after compression
            )

            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: bundleURL.appendingPathComponent("metadata.json"))

            // Compress if enabled
            let finalBackupURL: URL
            if compressionEnabled {
                finalBackupURL = try await compressBackup(bundleURL: bundleURL, targetURL: backupURL)
                try fileManager.removeItem(at: bundleURL)
            } else {
                try fileManager.moveItem(at: bundleURL, to: backupURL)
                finalBackupURL = backupURL
            }

            // Update statistics
            let attributes = try fileManager.attributesOfItem(atPath: finalBackupURL.path)
            backupSize = attributes[.size] as? Int64 ?? 0
            lastBackupDate = Date()
            backupStatus = .completed

            // Cleanup old backups
            cleanupOldBackups()

            // Save settings
            saveBackupSettings()

            logger.info("Backup completed successfully: \(finalBackupURL.lastPathComponent)")
            return BackupResult(success: true, error: nil, backupURL: finalBackupURL)

        } catch {
            backupStatus = .failed
            logger.error("Backup failed: \(error.localizedDescription)")
            return BackupResult(success: false, error: .backupFailed(error), backupURL: nil)
        }
    }

    func _restoreBackup(from backupURL: URL) async -> RestoreResult {
        backupStatus = .restoring

        do {
            guard let storeURL = swiftDataStoreURL else {
                logger.error("SwiftData store not found for restore")
                return RestoreResult(success: false, error: .storeNotFound)
            }

            // Create temporary extraction directory
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: tempDir)
            }

            // Extract backup
            if compressionEnabled {
                try await decompressBackup(backupURL: backupURL, to: tempDir)
            } else {
                try fileManager.copyItem(at: backupURL, to: tempDir.appendingPathComponent("backup"))
            }

            // Validate backup
            let extractedStoreURL = tempDir.appendingPathComponent("backup/store.sqlite")
            guard fileManager.fileExists(atPath: extractedStoreURL.path) else {
                logger.error("Invalid backup: store not found")
                return RestoreResult(success: false, error: .invalidBackup)
            }

            // Create backup of current store before restore
            _ = await _performBackup()

            // Replace current store
            try fileManager.removeItem(at: storeURL)
            try fileManager.copyItem(at: extractedStoreURL, to: storeURL)

            // Copy related files if they exist
            let walSource = tempDir.appendingPathComponent("backup/store.sqlite-wal")
            let shmSource = tempDir.appendingPathComponent("backup/store.sqlite-shm")

            if fileManager.fileExists(atPath: walSource.path) {
                try fileManager.copyItem(at: walSource, to: storeURL.appendingPathExtension("wal"))
            }

            if fileManager.fileExists(atPath: shmSource.path) {
                try fileManager.copyItem(at: shmSource, to: storeURL.appendingPathExtension("shm"))
            }

            backupStatus = .completed
            logger.info("Restore completed successfully from: \(backupURL.lastPathComponent)")
            return RestoreResult(success: true, error: nil)

        } catch {
            backupStatus = .failed
            logger.error("Restore failed: \(error.localizedDescription)")
            return RestoreResult(success: false, error: .restoreFailed(error))
        }
    }

    func _exportData(format: ExportFormat) async -> ExportResult {
        // Implementation for different export formats (JSON, CSV, etc.)
        logger.info("Export functionality will be implemented based on format: \(format)")
        return ExportResult(success: false, error: .notImplemented, exportURL: nil)
    }

    func _importData(from url: URL, format: ExportFormat) async -> ImportResult {
        // Implementation for different import formats
        logger.info("Import functionality will be implemented based on format: \(format)")
        return ImportResult(success: false, error: .notImplemented, importedCount: 0)
    }

    func compressBackup(bundleURL: URL, targetURL: URL) async throws -> URL {
        // Implement compression using native APIs
        // For now, just move the bundle
        try fileManager.moveItem(at: bundleURL, to: targetURL)
        return targetURL
    }

    func decompressBackup(backupURL: URL, to destination: URL) async throws {
        // Implement decompression
        // For now, just copy
        try fileManager.copyItem(at: backupURL, to: destination.appendingPathComponent("backup"))
    }

    func createBackupMetadata(from url: URL) -> BackupMetadata? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let creationDate = attributes[.creationDate] as? Date ?? Date()

            return BackupMetadata(
                version: "1.0",
                creationDate: creationDate,
                appVersion: "Unknown",
                noteCount: 0,
                url: url,
                fileSize: fileSize
            )
        } catch {
            logger.error("Failed to create metadata for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    func setupAutoBackup() {
        guard autoBackupEnabled else { return }

        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(withTimeInterval: backupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = await self?.performBackup()
            }
        }

        logger.info("Auto backup scheduled every \(self.backupInterval / 3600) hours")
    }

    func loadBackupSettings() {
        let defaults = UserDefaults.standard
        autoBackupEnabled = defaults.bool(forKey: "autoBackupEnabled")
        lastBackupDate = defaults.object(forKey: "lastBackupDate") as? Date
        backupSize = defaults.object(forKey: "backupSize") as? Int64 ?? 0
    }

    func saveBackupSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoBackupEnabled, forKey: "autoBackupEnabled")
        defaults.set(lastBackupDate, forKey: "lastBackupDate")
        defaults.set(backupSize, forKey: "backupSize")
    }
}

// MARK: - Supporting Types

enum BackupStatus {
    case idle
    case inProgress
    case restoring
    case completed
    case failed
}

enum ExportFormat: String, CustomStringConvertible {
    case json
    case csv
    case markdown

    var description: String { rawValue }
}

struct BackupResult: Sendable {
    let success: Bool
    let error: BackupError?
    let backupURL: URL?
}

struct RestoreResult: Sendable {
    let success: Bool
    let error: BackupError?
}

struct ExportResult: Sendable {
    let success: Bool
    let error: BackupError?
    let exportURL: URL?
}

struct ImportResult: Sendable {
    let success: Bool
    let error: BackupError?
    let importedCount: Int
}

enum BackupError: Error, LocalizedError {
    case storeNotFound
    case backupFailed(Error)
    case restoreFailed(Error)
    case invalidBackup
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "SwiftData store not found"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .restoreFailed(let error):
            return "Restore failed: \(error.localizedDescription)"
        case .invalidBackup:
            return "Invalid backup file"
        case .notImplemented:
            return "Feature not implemented"
        }
    }
}

struct BackupMetadata: Codable, Sendable {
    let version: String
    let creationDate: Date
    let appVersion: String
    let noteCount: Int
    let url: URL
    let fileSize: Int64
}

struct BackupStatistics: Sendable {
    let totalBackups: Int
    let totalSize: Int64
    let oldestBackup: Date?
    let newestBackup: Date?
    let lastBackupDate: Date?
}

