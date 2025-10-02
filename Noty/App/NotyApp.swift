//
//  NotyApp.swift
//  Noty
//
//  Created by Moheb Anwari on 05.08.25.
//

import SwiftUI

@main
struct NotyApp: App {
    @StateObject private var notesManager = NotesManager()
    @StateObject private var themeManager = ThemeManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notesManager)
                .environmentObject(themeManager)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
