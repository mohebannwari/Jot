import SwiftUI

/// Menu bar commands for note and folder management.
/// Replaces the default "New" item group with Jot-specific actions.
struct NoteManagementCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(.createNewNote)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Folder") {
                NotificationCenter.default.post(.createNewFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Move to Trash") {
                NotificationCenter.default.post(.trashFocusedNote)
            }
        }

        SwiftUI.CommandMenu("Navigate") {
            Button("Previous Note") {
                NotificationCenter.default.post(.navigateNote(.up))
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Next Note") {
                NotificationCenter.default.post(.navigateNote(.down))
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }
}
