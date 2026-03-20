//
//  JotApp.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authManager = NoteAuthenticationManager()
    @StateObject private var undoToastManager = UndoToastManager()

    init() {
        // Initialize SwiftData manager with error handling
        let manager: SimpleSwiftDataManager
        do {
            manager = try SimpleSwiftDataManager()
        } catch {
            fatalError("Failed to initialize data store: \(error). The app cannot continue without persistence.")
        }
        _notesManager = StateObject(wrappedValue: manager)
        SimpleSwiftDataManager.shared = manager

        // Clean up temporary files on app launch
        Self.cleanupTemporaryFiles()

        // Install Cmd+P handler at NSEvent level (bypasses SwiftUI/macOS print validation)
        PrintKeyHandler.shared.install()
    }

    /// Clean up temporary files that may have accumulated from previous sessions
    private static func cleanupTemporaryFiles() {
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
                NSLog("🧹 JotApp: Cleaned up %d temporary voice recording(s)", files.count)
            } catch {
                NSLog("🧹 JotApp: Failed to cleanup voice recordings: %@", error.localizedDescription)
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
            if cleanedCount > 0 {
                NSLog("🧹 JotApp: Cleaned up %d temporary image(s)", cleanedCount)
            }
        } catch {
            NSLog("🧹 JotApp: Failed to cleanup temp directory: %@", error.localizedDescription)
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
                .preferredColorScheme(themeManager.resolvedColorScheme)
                .containerShape(.rect(cornerRadius: 16))
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
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
            }
        }
        #endif
    }
}
