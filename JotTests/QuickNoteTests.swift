import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Jot

// MARK: - QuickNoteHotKey

final class QuickNoteHotKeyTests: XCTestCase {

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let original = QuickNoteHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuickNoteHotKey.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Default

    func testDefaultIsControlOptionCommandN() {
        let d = QuickNoteHotKey.default
        XCTAssertEqual(d.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(d.modifiers, UInt32(cmdKey | optionKey | controlKey))
    }

    // MARK: Cocoa -> Carbon translation (16 combinations)

    func testCocoaToCarbonAllSixteenCombinations() {
        let cases: [(NSEvent.ModifierFlags, UInt32)] = [
            ([],                                                    0),
            ([.command],                                            UInt32(cmdKey)),
            ([.option],                                             UInt32(optionKey)),
            ([.shift],                                              UInt32(shiftKey)),
            ([.control],                                            UInt32(controlKey)),
            ([.command, .option],                                   UInt32(cmdKey | optionKey)),
            ([.command, .shift],                                    UInt32(cmdKey | shiftKey)),
            ([.command, .control],                                  UInt32(cmdKey | controlKey)),
            ([.option, .shift],                                     UInt32(optionKey | shiftKey)),
            ([.option, .control],                                   UInt32(optionKey | controlKey)),
            ([.shift, .control],                                    UInt32(shiftKey | controlKey)),
            ([.command, .option, .shift],                           UInt32(cmdKey | optionKey | shiftKey)),
            ([.command, .option, .control],                         UInt32(cmdKey | optionKey | controlKey)),
            ([.command, .shift, .control],                          UInt32(cmdKey | shiftKey | controlKey)),
            ([.option, .shift, .control],                           UInt32(optionKey | shiftKey | controlKey)),
            ([.command, .option, .shift, .control],                 UInt32(cmdKey | optionKey | shiftKey | controlKey)),
        ]
        for (cocoa, expected) in cases {
            XCTAssertEqual(
                QuickNoteHotKey.carbonModifiers(from: cocoa),
                expected,
                "Failed for cocoa flags: \(cocoa.rawValue)"
            )
        }
    }

    // MARK: Display string

    func testDisplayStringOrderingAllFourModifiers() {
        let hk = QuickNoteHotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey | shiftKey | controlKey)
        )
        XCTAssertEqual(hk.displayString, "\u{2303}\u{2325}\u{21E7}\u{2318}N")
    }

    func testDisplayStringDefault() {
        XCTAssertEqual(QuickNoteHotKey.default.displayString, "\u{2303}\u{2325}\u{2318}N")
    }

    func testDisplayStringSingleModifier() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey))
        XCTAssertEqual(hk.displayString, "\u{2318}S")
    }

    func testDisplayStringFunctionKeyNoModifiers() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_F5), modifiers: 0)
        XCTAssertEqual(hk.displayString, "F5")
    }

    func testDisplayStringUnknownKeyFallback() {
        let hk = QuickNoteHotKey(keyCode: 0xFF, modifiers: UInt32(cmdKey))
        XCTAssertEqual(hk.displayString, "\u{2318}Key 0xFF")
    }

    // MARK: hasAnyModifier

    func testHasAnyModifierTrueForSingleModifier() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))
        XCTAssertTrue(hk.hasAnyModifier)
    }

    func testHasAnyModifierFalseForBareKey() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: 0)
        XCTAssertFalse(hk.hasAnyModifier)
    }
}
