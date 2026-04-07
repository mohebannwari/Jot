import Foundation
import AppKit
import Combine
import OSLog

/// Manages full-app JSON backups to a user-chosen folder with security-scoped bookmarks.
@MainActor
final class BackupManager: ObservableObject {
    static let shared = BackupManager()

    private let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")
    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    private var autoBackupTimer: Timer?

    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var backupFolderName: String?
    @Published private(set) var isBackingUp = false
    @Published private(set) var isBookmarkStale = false

    struct BackupManifest: Codable {
        let appVersion: String
        let schemaVersion: Int
        let timestamp: Date
        let noteCount: Int
        let folderCount: Int
    }

    private init() {
        lastBackupDate = userDefaults.object(forKey: ThemeManager.lastBackupDateKey) as? Date
        updateBackupFolderName()
    }

    // MARK: - Folder Selection

    /// Presents an open panel for the user to choose a backup destination folder.
    func pickBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for Jot backups"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmark, forKey: ThemeManager.backupFolderBookmarkKey)
            isBookmarkStale = false
            updateBackupFolderName()
            logger.info("Saved backup folder bookmark: \(url.path)")
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error)")
        }
    }

    /// Resolves the security-scoped bookmark to a usable URL.
    func resolvedBackupFolderURL() -> URL? {
        guard let bookmarkData = userDefaults.data(forKey: ThemeManager.backupFolderBookmarkKey) else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                isBookmarkStale = true
                logger.warning("Backup folder bookmark is stale")
                // Try to refresh the bookmark
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let newBookmark = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        userDefaults.set(newBookmark, forKey: ThemeManager.backupFolderBookmarkKey)
                        isBookmarkStale = false
                    }
                }
            }

            return url
        } catch {
            logger.error("Failed to resolve backup folder bookmark: \(error)")
            isBookmarkStale = true
            return nil
        }
    }

    // MARK: - Backup

    /// Performs a full backup of all notes, folders, images, and files.
    func performBackup(notesManager: SimpleSwiftDataManager) async -> Bool {
        guard let baseURL = resolvedBackupFolderURL() else {
            logger.error("No backup folder configured")
            return false
        }

        guard baseURL.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped backup folder")
            return false
        }
        defer { baseURL.stopAccessingSecurityScopedResource() }

        isBackingUp = true
        defer { isBackingUp = false }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let timestamp = dateFormatter.string(from: Date())
        let backupFolderName = "Jot-Backup-\(timestamp)"
        let backupURL = baseURL.appendingPathComponent(backupFolderName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

            // Serialize notes
            let allNotes = gatherAllNotes(from: notesManager)
            let notesData = try JSONEncoder.jotBackup.encode(allNotes)
            try notesData.write(to: backupURL.appendingPathComponent("notes.json"))

            // Serialize folders
            notesManager.loadArchivedFolders()
            let allFolders = notesManager.folders + notesManager.archivedFolders
            let foldersData = try JSONEncoder.jotBackup.encode(allFolders)
            try foldersData.write(to: backupURL.appendingPathComponent("folders.json"))

            // Write manifest
            let manifest = BackupManifest(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                schemaVersion: 1,
                timestamp: Date(),
                noteCount: allNotes.count,
                folderCount: allFolders.count
            )
            let manifestData = try JSONEncoder.jotBackup.encode(manifest)
            try manifestData.write(to: backupURL.appendingPathComponent("manifest.json"))

            // Copy image and file directories
            copyDirectory(named: "JotImages", to: backupURL)
            copyDirectory(named: "JotFiles", to: backupURL)

            // Validate by reading manifest back
            let readBack = try Data(contentsOf: backupURL.appendingPathComponent("manifest.json"))
            _ = try JSONDecoder.jotBackup.decode(BackupManifest.self, from: readBack)

            // Update last backup date
            let now = Date()
            lastBackupDate = now
            userDefaults.set(now, forKey: ThemeManager.lastBackupDateKey)

            logger.info("Backup completed: \(backupFolderName) (\(allNotes.count) notes, \(allFolders.count) folders)")

            // Prune old backups
            pruneOldBackups(in: baseURL)

            return true
        } catch {
            logger.error("Backup failed: \(error)")
            // Clean up partial backup
            try? fileManager.removeItem(at: backupURL)
            return false
        }
    }

    /// Lists available backups in the configured folder.
    func listAvailableBackups() -> [(manifest: BackupManifest, url: URL)] {
        guard let baseURL = resolvedBackupFolderURL() else { return [] }

        guard baseURL.startAccessingSecurityScopedResource() else { return [] }
        defer { baseURL.stopAccessingSecurityScopedResource() }

        var results: [(manifest: BackupManifest, url: URL)] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for dir in contents {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder.jotBackup.decode(BackupManifest.self, from: data) {
                results.append((manifest: manifest, url: dir))
            }
        }

        return results.sorted { $0.manifest.timestamp > $1.manifest.timestamp }
    }

    /// Initiates a restore: writes the backup path to UserDefaults and terminates the app.
    /// On next launch, JotApp.init() checks this flag and performs the actual restore.
    func restoreBackup(_ backupURL: URL) {
        userDefaults.set(backupURL.path, forKey: "pendingRestoreBackupPath")
        logger.info("Restore flag set for: \(backupURL.path). Terminating app.")
        NSApp.terminate(nil)
    }

    /// Checks for and executes a pending restore on app launch.
    /// Returns the security-scoped URL that must be stopped after `performPostInitRestore`.
    /// Must be called BEFORE SimpleSwiftDataManager is constructed.
    static func checkAndPerformPendingRestore() -> URL? {
        let defaults = UserDefaults.standard
        guard let backupPath = defaults.string(forKey: "pendingRestoreBackupPath") else {
            return nil
        }
        defaults.removeObject(forKey: "pendingRestoreBackupPath")

        let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")
        let backupURL = URL(fileURLWithPath: backupPath)
        let fm = FileManager.default

        // Resolve security-scoped bookmark for the parent folder
        var accessedURL: URL?
        if let bookmarkData = defaults.data(forKey: ThemeManager.backupFolderBookmarkKey) {
            var isStale = false
            if let parentURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if parentURL.startAccessingSecurityScopedResource() {
                    accessedURL = parentURL
                }
            }
        }

        guard fm.fileExists(atPath: backupURL.appendingPathComponent("manifest.json").path) else {
            logger.error("Pending restore aborted: manifest.json not found at \(backupPath)")
            accessedURL?.stopAccessingSecurityScopedResource()
            return nil
        }

        // Locate and replace the SwiftData store
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("default.store", isDirectory: false)

        // Remove existing SwiftData files
        let storeExtensions = ["", "-wal", "-shm"]
        for ext in storeExtensions {
            let file = URL(fileURLWithPath: storeDir.path + ext)
            try? fm.removeItem(at: file)
        }

        logger.info("Pending restore: cleared existing store. Will import data on next manager init.")

        // Store the backup path for import after SimpleSwiftDataManager initializes
        defaults.set(backupPath, forKey: "pendingImportBackupPath")
        return accessedURL
    }

    /// Called after SimpleSwiftDataManager is initialized to import backup data.
    static func performPostInitRestore(into notesManager: SimpleSwiftDataManager) {
        let defaults = UserDefaults.standard
        guard let backupPath = defaults.string(forKey: "pendingImportBackupPath") else { return }
        defaults.removeObject(forKey: "pendingImportBackupPath")

        let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")
        let backupURL = URL(fileURLWithPath: backupPath)

        do {
            let notesData = try Data(contentsOf: backupURL.appendingPathComponent("notes.json"))
            let notes = try JSONDecoder.jotBackup.decode([Note].self, from: notesData)

            let foldersData = try Data(contentsOf: backupURL.appendingPathComponent("folders.json"))
            let folders = try JSONDecoder.jotBackup.decode([Folder].self, from: foldersData)

            notesManager.importBackup(notes: notes, folders: folders)

            // Restore images and files into the App Group container
            let restoreBase = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID)
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            try restoreDirectory(named: "JotImages", from: backupURL, to: restoreBase)
            try restoreDirectory(named: "JotFiles", from: backupURL, to: restoreBase)

            logger.info("Restore complete: \(notes.count) notes, \(folders.count) folders")
        } catch {
            logger.error("Post-init restore failed: \(error)")
        }
    }

    // MARK: - Auto Backup

    /// Checks if an automatic backup is due based on frequency setting, and runs it if so.
    func autoBackupIfDue(notesManager: SimpleSwiftDataManager) {
        let frequency = BackupFrequency(
            rawValue: userDefaults.string(forKey: ThemeManager.backupFrequencyKey) ?? "manual"
        ) ?? .manual

        guard frequency != .manual else { return }
        guard resolvedBackupFolderURL() != nil else { return }

        let interval: TimeInterval = frequency == .daily ? 86400 : 604800
        let lastBackup = userDefaults.object(forKey: ThemeManager.lastBackupDateKey) as? Date ?? .distantPast

        guard Date().timeIntervalSince(lastBackup) >= interval else { return }

        Task { [weak self] in
            guard let self else { return }
            _ = await performBackup(notesManager: notesManager)
        }
    }

    /// Schedules periodic backup checks based on the frequency setting.
    func scheduleAutoBackup(notesManager: SimpleSwiftDataManager) {
        autoBackupTimer?.invalidate()

        let frequency = BackupFrequency(
            rawValue: userDefaults.string(forKey: ThemeManager.backupFrequencyKey) ?? "manual"
        ) ?? .manual

        guard frequency != .manual else { return }

        // Check every hour if a backup is due
        autoBackupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self, weak notesManager] _ in
            Task { @MainActor in
                guard let notesManager else { return }
                self?.autoBackupIfDue(notesManager: notesManager)
            }
        }
    }

    // MARK: - Private Helpers

    private func gatherAllNotes(from manager: SimpleSwiftDataManager) -> [Note] {
        // Ensure archived and deleted notes are loaded before backup
        manager.loadArchivedNotes()
        manager.loadDeletedNotes()

        var all = manager.notes
        all.append(contentsOf: manager.archivedNotes)
        all.append(contentsOf: manager.deletedNotes)
        return all
    }

    private static let appGroupID = "group.com.mohebanwari.Jot"

    private func copyDirectory(named name: String, to backupURL: URL) {
        let baseDir = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID)
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sourceDir = baseDir.appendingPathComponent(name, isDirectory: true)

        guard fileManager.fileExists(atPath: sourceDir.path) else { return }

        let destDir = backupURL.appendingPathComponent(name, isDirectory: true)
        do {
            try fileManager.copyItem(at: sourceDir, to: destDir)
            logger.info("Copied \(name) directory to backup")
        } catch {
            logger.error("Failed to copy \(name) directory: \(error)")
        }
    }

    private static func restoreDirectory(named name: String, from backupURL: URL, to documentsDir: URL) throws {
        let fm = FileManager.default
        let sourceDir = backupURL.appendingPathComponent(name, isDirectory: true)
        let destDir = documentsDir.appendingPathComponent(name, isDirectory: true)

        guard fm.fileExists(atPath: sourceDir.path) else { return }

        // Remove existing and replace
        if fm.fileExists(atPath: destDir.path) {
            try fm.removeItem(at: destDir)
        }
        try fm.copyItem(at: sourceDir, to: destDir)
    }

    /// Prunes old backups in the given directory (which must already have security-scoped access).
    private func pruneOldBackups(in baseURL: URL) {
        let maxCount = userDefaults.integer(forKey: ThemeManager.backupMaxCountKey)
        guard maxCount > 0 else { return }

        // Enumerate backups directly using the already-open baseURL (avoid re-opening the bookmark)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var backups: [(timestamp: Date, url: URL)] = []
        for dir in contents {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder.jotBackup.decode(BackupManifest.self, from: data) else { continue }
            backups.append((timestamp: manifest.timestamp, url: dir))
        }

        backups.sort { $0.timestamp > $1.timestamp }
        guard backups.count > maxCount else { return }

        let toRemove = backups.suffix(from: maxCount)
        for backup in toRemove {
            do {
                try fileManager.removeItem(at: backup.url)
                logger.info("Pruned old backup: \(backup.url.lastPathComponent)")
            } catch {
                logger.error("Failed to prune backup: \(error)")
            }
        }
    }

    private func updateBackupFolderName() {
        if let url = resolvedBackupFolderURL() {
            backupFolderName = url.lastPathComponent
        } else {
            backupFolderName = nil
        }
    }
}

// MARK: - JSON Codec Extensions

private extension JSONEncoder {
    static let jotBackup: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let jotBackup: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
