//
//  NotyApp.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

@main
struct NotyApp: App {
    @StateObject private var notesManager: SimpleSwiftDataManager
    @StateObject private var themeManager = ThemeManager()

    init() {
        // Initialize SwiftData manager with error handling
        let manager: SimpleSwiftDataManager
        do {
            manager = try SimpleSwiftDataManager()
        } catch {
            print("Failed to initialize SimpleSwiftDataManager: \(error)")
            // Fallback to in-memory storage
            fatalError("Cannot initialize database. Please check logs.")
        }
        _notesManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .containerShape(.rect(cornerRadius: 16))
        }
        .windowStyle(.hiddenTitleBar)
    }
}
