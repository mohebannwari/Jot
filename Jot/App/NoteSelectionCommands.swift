import SwiftUI

enum NoteSelectionCommandAction: String {
    case selectAll
    case clearSelection
    case deleteSelection
    case exportSelection
    case moveSelection
}

extension Notification.Name {
    static let noteSelectionCommandTriggered = Notification.Name("noteSelectionCommandTriggered")
}

struct NoteSelectionCommands: Commands {
    var body: some Commands {
        SwiftUI.CommandMenu("Selection") {
            Button("Select All Notes") {
                post(.selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Clear Note Selection") {
                post(.clearSelection)
            }
            .keyboardShortcut(.escape, modifiers: [])

            Divider()

            Button("Delete Selected Notes") {
                post(.deleteSelection)
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Export Selected Notes") {
                post(.exportSelection)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Move Selected Notes") {
                post(.moveSelection)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    private func post(_ action: NoteSelectionCommandAction) {
        NotificationCenter.default.post(
            name: .noteSelectionCommandTriggered,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
    }
}
