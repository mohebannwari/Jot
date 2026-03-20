//
//  JotShortcutsProvider.swift
//  Jot
//

import AppIntents

struct JotShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)",
                "Make a note in \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: [
                "Open a note in \(.applicationName)",
                "Show note in \(.applicationName)"
            ],
            shortTitle: "Open Note",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: [
                "Search notes in \(.applicationName)",
                "Find notes in \(.applicationName)"
            ],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AppendToNoteIntent(),
            phrases: [
                "Append to a note in \(.applicationName)",
                "Add text to a note in \(.applicationName)"
            ],
            shortTitle: "Append to Note",
            systemImageName: "text.append"
        )
    }
}
