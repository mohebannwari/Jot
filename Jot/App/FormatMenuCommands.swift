import SwiftUI

/// Format menu providing discoverability for text formatting shortcuts.
/// The actual key handling when the editor is focused happens in
/// TodoEditorRepresentable's keyDown -- these menu items fire when
/// the editor is NOT the first responder, or serve as visual reference.
struct FormatMenuCommands: Commands {
    var body: some Commands {
        SwiftUI.CommandMenu("Format") {
            Button("Bold") { postFormat("bold") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { postFormat("italic") }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { postFormat("underline") }
                .keyboardShortcut("u", modifiers: .command)
            Button("Strikethrough") { postFormat("strikethrough") }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()

            Button("Heading 1") { postFormat("h1") }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading 2") { postFormat("h2") }
                .keyboardShortcut("2", modifiers: .command)
            Button("Heading 3") { postFormat("h3") }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Bullet List") { postFormat("bulletList") }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { postFormat("numberedList") }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Block Quote") { postFormat("blockQuote") }
                .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button("Highlight") { postFormat("highlight") }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Insert Link") { postFormat("insertLink") }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

    private func postFormat(_ action: String) {
        NotificationCenter.default.post(
            name: .formatMenuAction,
            object: nil,
            userInfo: ["action": action]
        )
    }
}
