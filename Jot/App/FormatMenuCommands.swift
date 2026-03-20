import SwiftUI

/// Format menu providing **discoverability** for text formatting shortcuts.
///
/// These menu items exist so users can see keyboard shortcuts in the menu bar.
/// The actual key handling happens in TodoEditorRepresentable's keyDown/
/// performKeyEquivalent when the editor has focus (AppKit responder chain
/// intercepts before the SwiftUI menu). When the editor is NOT focused,
/// formatting has no target -- this is correct behavior, same as any
/// text editor that greys out formatting when no text view is active.
struct FormatMenuCommands: Commands {
    var body: some Commands {
        SwiftUI.CommandMenu("Format") {
            Button("Bold") { }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { }
                .keyboardShortcut("i", modifiers: .command)
            Button("Underline") { }
                .keyboardShortcut("u", modifiers: .command)
            Button("Strikethrough") { }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()

            Button("Heading 1") { }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading 2") { }
                .keyboardShortcut("2", modifiers: .command)
            Button("Heading 3") { }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Bullet List") { }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Block Quote") { }
                .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button("Highlight") { }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Insert Link") { }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}
