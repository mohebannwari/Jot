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

    struct BackupSnapshot {
        let notes: [Note]
        let folders: [Folder]
    }

    struct ValidatedRestorePayload {
        let backupURL: URL
        let notes: [Note]
        let folders: [Folder]
    }

    private enum RestoreValidationError: LocalizedError {
        case missingRequiredFile(String)

        var errorDescription: String? {
            switch self {
            case .missingRequiredFile(let name):
                return "Missing required restore file: \(name)"
            }
        }
    }

    private static var pendingValidatedRestore: ValidatedRestorePayload?

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

            let snapshot = try backupSnapshot(from: notesManager)

            // Serialize notes
            let notesData = try JSONEncoder.jotBackup.encode(snapshot.notes)
            try notesData.write(to: backupURL.appendingPathComponent("notes.json"))

            // Serialize folders
            let foldersData = try JSONEncoder.jotBackup.encode(snapshot.folders)
            try foldersData.write(to: backupURL.appendingPathComponent("folders.json"))

            // Write manifest
            let manifest = BackupManifest(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                schemaVersion: 1,
                timestamp: Date(),
                noteCount: snapshot.notes.count,
                folderCount: snapshot.folders.count
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

            logger.info("Backup completed: \(backupFolderName) (\(snapshot.notes.count) notes, \(snapshot.folders.count) folders)")

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

    /// Initiates a restore: flushes pending editor writes, writes the backup path to UserDefaults,
    /// then terminates the app. On next launch `JotApp.init()` finds the flag and performs the
    /// actual restore.
    ///
    /// The flush step matters because the editor debounces serialization by 150ms; without it,
    /// any text typed in the last 150ms before the user confirms "Restore" would be lost when
    /// `NSApp.terminate(nil)` exits the process before the debounce timer fires.
    func restoreBackup(_ backupURL: URL) {
        Self.prepareRestore(
            backupPath: backupURL.path,
            userDefaults: userDefaults,
            notificationCenter: .default)
        logger.info("Restore flag set for: \(backupURL.path). Terminating app.")
        NSApp.terminate(nil)
    }

    /// Side-effect-only seam for `restoreBackup`, exposed for testing. Writes the pending-restore
    /// flag to `userDefaults` and broadcasts `.jotFlushEditorSerializationBeforeTerminate` so every
    /// live editor Coordinator flushes its debounced serialization before the caller terminates.
    static func prepareRestore(
        backupPath: String,
        userDefaults: UserDefaults,
        notificationCenter: NotificationCenter
    ) {
        // Order: flush first so in-flight edits land on the binding, THEN write the restore flag.
        // Reversing the order would be fine today, but this ordering keeps the invariant obvious:
        // "by the time the flag is persisted, all editors have drained."
        notificationCenter.post(
            name: .jotFlushEditorSerializationBeforeTerminate,
            object: nil)
        userDefaults.set(backupPath, forKey: "pendingRestoreBackupPath")
    }

    /// Checks for and executes a pending restore on app launch.
    /// Returns the security-scoped URL that must be stopped after `performPostInitRestore`.
    /// Must be called BEFORE SimpleSwiftDataManager is constructed.
    static func checkAndPerformPendingRestore(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        storeBaseURL: URL? = nil
    ) -> URL? {
        let defaults = userDefaults
        guard let backupPath = defaults.string(forKey: "pendingRestoreBackupPath") else {
            return nil
        }
        defaults.removeObject(forKey: "pendingRestoreBackupPath")

        let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")
        let backupURL = URL(fileURLWithPath: backupPath)
        let fm = fileManager

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

        do {
            let validatedRestore = try validateRestorePayload(at: backupURL, fileManager: fm)
            try removeStoreFiles(
                at: storeBaseURL ?? defaultStoreBaseURL(using: fm),
                fileManager: fm
            )
            pendingValidatedRestore = validatedRestore
            defaults.set(backupPath, forKey: "pendingImportBackupPath")
            logger.info("Pending restore validated and staged for import from \(backupPath)")
            return accessedURL
        } catch {
            pendingValidatedRestore = nil
            defaults.removeObject(forKey: "pendingImportBackupPath")
            logger.error("Pending restore aborted before store replacement: \(error.localizedDescription)")
            accessedURL?.stopAccessingSecurityScopedResource()
            return nil
        }
    }

    /// Called after SimpleSwiftDataManager is initialized to import backup data.
    static func performPostInitRestore(
        into notesManager: SimpleSwiftDataManager,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let defaults = userDefaults
        let payload: ValidatedRestorePayload

        if let stagedPayload = pendingValidatedRestore {
            payload = stagedPayload
            pendingValidatedRestore = nil
            defaults.removeObject(forKey: "pendingImportBackupPath")
        } else {
            guard let backupPath = defaults.string(forKey: "pendingImportBackupPath") else { return }
            defaults.removeObject(forKey: "pendingImportBackupPath")
            do {
                payload = try validateRestorePayload(
                    at: URL(fileURLWithPath: backupPath),
                    fileManager: fileManager
                )
            } catch {
                let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")
                logger.error("Post-init restore failed validation: \(error.localizedDescription)")
                return
            }
        }

        let logger = Logger(subsystem: "com.jot.app", category: "BackupManager")

        do {
            notesManager.importBackup(notes: payload.notes, folders: payload.folders)

            // Restore images and files into the App Group container
            let restoreBase = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID)
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            try restoreDirectory(named: "JotImages", from: payload.backupURL, to: restoreBase)
            try restoreDirectory(named: "JotFiles", from: payload.backupURL, to: restoreBase)

            logger.info("Restore complete: \(payload.notes.count) notes, \(payload.folders.count) folders")
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

        let lastBackup = userDefaults.object(forKey: ThemeManager.lastBackupDateKey) as? Date ?? .distantPast
        guard shouldRunAutoBackup(
            frequency: frequency,
            lastBackupDate: lastBackup,
            hasBackupDestination: resolvedBackupFolderURL() != nil,
            hasLoadedInitialNotes: notesManager.hasLoadedInitialNotes
        ) else { return }

        Task { @MainActor [weak self] in
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
        autoBackupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let notesManager = SimpleSwiftDataManager.shared else { return }
                self.autoBackupIfDue(notesManager: notesManager)
            }
        }
    }

    // MARK: - Private Helpers

    func backupSnapshot(from manager: SimpleSwiftDataManager) throws -> BackupSnapshot {
        BackupSnapshot(
            notes: try manager.allNotesForBackup(),
            folders: try manager.allFoldersForBackup()
        )
    }

    func shouldRunAutoBackup(
        frequency: BackupFrequency,
        lastBackupDate: Date,
        hasBackupDestination: Bool,
        hasLoadedInitialNotes: Bool,
        now: Date = Date()
    ) -> Bool {
        guard frequency != .manual else { return false }
        guard hasBackupDestination else { return false }
        guard hasLoadedInitialNotes else { return false }

        let interval: TimeInterval = frequency == .daily ? 86400 : 604800
        return now.timeIntervalSince(lastBackupDate) >= interval
    }

    private static let appGroupID = "group.com.mohebanwari.Jot"

    private static func validateRestorePayload(
        at backupURL: URL,
        fileManager: FileManager
    ) throws -> ValidatedRestorePayload {
        let manifestURL = backupURL.appendingPathComponent("manifest.json")
        let notesURL = backupURL.appendingPathComponent("notes.json")
        let foldersURL = backupURL.appendingPathComponent("folders.json")

        for url in [manifestURL, notesURL, foldersURL] {
            guard fileManager.fileExists(atPath: url.path) else {
                throw RestoreValidationError.missingRequiredFile(url.lastPathComponent)
            }
        }

        _ = try JSONDecoder.jotBackup.decode(
            BackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let notes = try JSONDecoder.jotBackup.decode([Note].self, from: Data(contentsOf: notesURL))
        let folders = try JSONDecoder.jotBackup.decode([Folder].self, from: Data(contentsOf: foldersURL))

        return ValidatedRestorePayload(
            backupURL: backupURL,
            notes: notes,
            folders: folders
        )
    }

    private static func defaultStoreBaseURL(using fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("default.store", isDirectory: false)
    }

    private static func removeStoreFiles(at storeBaseURL: URL, fileManager: FileManager) throws {
        for ext in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: storeBaseURL.path + ext)
            if fileManager.fileExists(atPath: file.path) {
                try fileManager.removeItem(at: file)
            }
        }
    }

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
