//
//  QuickNoteHotKey.swift
//  Jot
//
//  Value type representing a global keyboard shortcut for Quick Notes.
//  Stores a Carbon virtual key code + Carbon modifier bitmask (not Cocoa).
//  Codable so it can persist to UserDefaults as JSON.
//

import AppKit
import Carbon.HIToolbox

struct QuickNoteHotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon bitmask: cmdKey | optionKey | shiftKey | controlKey

    /// The factory default: Command + Shift + J.
    /// J is mnemonic for "Jot"; ⌃⌥⌘N collides with too many existing app
    /// shortcuts (New-anything is almost universally mapped), so ⌘⇧J was
    /// chosen as the least-conflicting modifier-plus-mnemonic combination.
    static let `default` = QuickNoteHotKey(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// True if the hotkey has at least one modifier. Required for a valid global
    /// hotkey — pure letter keys would block normal typing system-wide.
    var hasAnyModifier: Bool {
        modifiers & UInt32(cmdKey | optionKey | shiftKey | controlKey) != 0
    }

    /// Human-readable chord display, e.g. "⌃⌥⌘N". Order matches Apple conventions:
    /// Control, Option, Shift, Command, then the key glyph.
    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0  { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0   { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0     { result += "⌘" }
        result += Self.keyCodeDisplayString(for: keyCode)
        return result
    }

    // MARK: - Cocoa -> Carbon translation

    /// Convert a Cocoa `NSEvent.ModifierFlags` bitmask into a Carbon bitmask.
    /// Only the four common modifiers are considered — function, capsLock, etc.
    /// are not valid for global hotkey registration.
    static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoa.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoa.contains(.option)  { carbon |= UInt32(optionKey) }
        if cocoa.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if cocoa.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: - Key code glyph table

    private static let keyCodeGlyphs: [UInt32: String] = [
        // Letters
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        // Digits
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        // Function keys
        UInt32(kVK_F1): "F1",   UInt32(kVK_F2): "F2",   UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",   UInt32(kVK_F5): "F5",   UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",   UInt32(kVK_F8): "F8",   UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        // Specials
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "\u{21A9}",
        UInt32(kVK_Tab): "\u{21E5}",
        UInt32(kVK_Escape): "\u{238B}",
        UInt32(kVK_Delete): "\u{232B}",
        UInt32(kVK_ForwardDelete): "\u{2326}",
    ]

    private static func keyCodeDisplayString(for keyCode: UInt32) -> String {
        keyCodeGlyphs[keyCode] ?? String(format: "Key 0x%02X", keyCode)
    }
}

// MARK: - Convenience loaders

extension QuickNoteHotKey {
    /// Reads the hotkey from `UserDefaults.standard` using the same key
    /// ThemeManager uses. This is a convenience for `JotApp.init`, where we
    /// need to install the hotkey before ThemeManager is constructed.
    static func loadFromStandardDefaults() -> QuickNoteHotKey? {
        guard let data = UserDefaults.standard.data(forKey: ThemeManager.quickNoteHotKeyKey),
              let decoded = try? JSONDecoder().decode(QuickNoteHotKey.self, from: data) else {
            return nil
        }
        return decoded
    }
}
