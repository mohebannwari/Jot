//
//  JotApp.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import os
import SwiftUI

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authManager = NoteAuthenticationManager()
    @StateObject private var undoToastManager = UndoToastManager()
    @StateObject private var updateManager = UpdateManager()
    #if DEBUG
    @StateObject private var buildWatcher = BuildWatcherManager()
    #endif

    @MainActor
    init() {
        // Check for pending backup restore BEFORE constructing the data store
        let restoreAccessURL = BackupManager.checkAndPerformPendingRestore()

        // Initialize SwiftData manager with error handling
        let manager: SimpleSwiftDataManager
        do {
            manager = try SimpleSwiftDataManager()
        } catch {
            fatalError("Failed to initialize data store: \(error). The app cannot continue without persistence.")
        }
        _notesManager = StateObject(wrappedValue: manager)
        SimpleSwiftDataManager.shared = manager

        // Complete backup restore if pending (imports data into the fresh store)
        BackupManager.performPostInitRestore(into: manager)
        restoreAccessURL?.stopAccessingSecurityScopedResource()

        // Migrate file/image storage from sandbox to App Group container (one-time)
        FileAttachmentStorageManager.shared.migrateFromSandboxIfNeeded()
        ImageStorageManager.shared.migrateFromSandboxIfNeeded()

        // Prune expired version snapshots
        let retentionDays = UserDefaults.standard.integer(forKey: ThemeManager.versionRetentionDaysKey)
        if retentionDays > 0 {
            NoteVersionManager.shared.pruneVersions(retentionDays: retentionDays, in: manager.modelContext)
        }

        // Start auto-backup timer if configured
        BackupManager.shared.autoBackupIfDue(notesManager: manager)
        BackupManager.shared.scheduleAutoBackup(notesManager: manager)

        // Clean up temporary files on app launch
        Self.cleanupTemporaryFiles()

        // Install Cmd+P handler at NSEvent level (bypasses SwiftUI/macOS print validation)
        PrintKeyHandler.shared.install()

        // Install the Quick Notes global hotkey. Reads the stored chord from
        // UserDefaults directly so this works regardless of ThemeManager's
        // construction order. Falls back to the factory default on first launch.
        let storedHotKey = QuickNoteHotKey.loadFromStandardDefaults() ?? .default
        GlobalHotKeyManager.shared.onFire = {
            QuickNoteWindowController.shared.showPanel()
        }
        GlobalHotKeyManager.shared.install(storedHotKey)
    }

    /// Clean up temporary files that may have accumulated from previous sessions
    private static func cleanupTemporaryFiles() {
        let logger = Logger(subsystem: "com.jot", category: "JotApp")
        let fileManager = FileManager.default
        let tmpDirectory = fileManager.temporaryDirectory

        // Clean up voice recording directory
        let micCaptureDir = tmpDirectory.appendingPathComponent("MicCapture", isDirectory: true)
        if fileManager.fileExists(atPath: micCaptureDir.path) {
            do {
                let files = try fileManager.contentsOfDirectory(at: micCaptureDir, includingPropertiesForKeys: nil)
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            } catch {
                logger.error("cleanupTemporaryFiles: Failed to cleanup voice recordings: \(error.localizedDescription)")
            }
        }

        // Clean up orphaned temporary image files (UUID-named files in tmp root)
        do {
            let files = try fileManager.contentsOfDirectory(at: tmpDirectory, includingPropertiesForKeys: [.isRegularFileKey])
            var cleanedCount = 0
            for file in files {
                // Check if it's a regular file with UUID-like name pattern and image extension
                let filename = file.lastPathComponent
                let isImage = ["jpg", "jpeg", "png", "heic", "heif"].contains(file.pathExtension.lowercased())

                // Only clean up if it looks like our temp files (UUID pattern)
                if isImage && filename.count > 30 {  // UUID filenames are typically 36+ chars
                    try? fileManager.removeItem(at: file)
                    cleanedCount += 1
                }
            }
        } catch {
            logger.error("cleanupTemporaryFiles: Failed to cleanup temp directory: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 815, minHeight: 600)
                .environmentObject(notesManager)
                .environmentObject(themeManager)
                .environmentObject(authManager)
                .environmentObject(undoToastManager)
                .environmentObject(updateManager)
                #if DEBUG
                .environmentObject(buildWatcher)
                #endif
                .preferredColorScheme(themeManager.resolvedColorScheme)
                .containerShape(.rect(cornerRadius: 16))
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragDisabledIfAvailable()
        .commands {
            NoteSelectionCommands()
            NoteManagementCommands()
            FormatMenuCommands()
            // Replace system Print menu with empty group to suppress macOS's
            // printing validation. Cmd+P is handled by PrintKeyHandler via NSEvent.
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                }
            }
        }
        #endif
    }
}
