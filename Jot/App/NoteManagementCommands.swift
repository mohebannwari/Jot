import SwiftUI

/// Menu bar commands for note and folder management.
/// Replaces the default "New" item group with Jot-specific actions.
struct NoteManagementCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(name: .createNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                NotificationCenter.default.post(name: .createNewFolder, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Move to Trash") {
                NotificationCenter.default.post(name: .trashFocusedNote, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        SwiftUI.CommandMenu("Navigate") {
            Button("Previous Note") {
                NotificationCenter.default.post(
                    name: .navigateNote,
                    object: nil,
                    userInfo: ["direction": "up"]
                )
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Next Note") {
                NotificationCenter.default.post(
                    name: .navigateNote,
                    object: nil,
                    userInfo: ["direction": "down"]
                )
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }
}
