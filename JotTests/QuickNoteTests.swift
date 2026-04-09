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

    func testDefaultIsCommandShiftJ() {
        let d = QuickNoteHotKey.default
        XCTAssertEqual(d.keyCode, UInt32(kVK_ANSI_J))
        XCTAssertEqual(d.modifiers, UInt32(cmdKey | shiftKey))
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
        // ⇧⌘J — display order is Control, Option, Shift, Command, then key
        XCTAssertEqual(QuickNoteHotKey.default.displayString, "\u{21E7}\u{2318}J")
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

// MARK: - ThemeManager Quick Notes persistence

final class ThemeManagerQuickNoteTests: XCTestCase {

    func testDefaultHotKeyIsFactoryDefaultWhenNothingStored() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager.quickNoteHotKey, QuickNoteHotKey.default)
    }

    func testSettingHotKeyPersistsToDefaults() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        let newHotKey = QuickNoteHotKey(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        manager.quickNoteHotKey = newHotKey

        let raw = try XCTUnwrap(defaults.data(forKey: ThemeManager.quickNoteHotKeyKey))
        let decoded = try JSONDecoder().decode(QuickNoteHotKey.self, from: raw)
        XCTAssertEqual(decoded, newHotKey)
    }

    func testInitReadsPersistedHotKey() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stored = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: ThemeManager.quickNoteHotKeyKey)

        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager.quickNoteHotKey, stored)
    }

    func testClearingHotKeyRemovesFromDefaults() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.quickNoteHotKey = QuickNoteHotKey(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey)
        )
        manager.quickNoteHotKey = nil

        XCTAssertNil(defaults.data(forKey: ThemeManager.quickNoteHotKeyKey))
        XCTAssertNil(manager.quickNoteHotKey)
    }

    func testFolderIDPersistenceRoundTrip() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertNil(manager.quickNotesFolderID)

        let id = UUID()
        manager.quickNotesFolderID = id
        XCTAssertEqual(defaults.string(forKey: ThemeManager.quickNotesFolderIDKey), id.uuidString)

        let manager2 = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager2.quickNotesFolderID, id)
    }

    func testClearingFolderIDRemovesFromDefaults() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.quickNotesFolderID = UUID()
        manager.quickNotesFolderID = nil

        XCTAssertNil(defaults.string(forKey: ThemeManager.quickNotesFolderIDKey))
        XCTAssertNil(manager.quickNotesFolderID)
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "QuickNoteThemeManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

// MARK: - QuickNoteService

@MainActor
final class QuickNoteServiceTests: XCTestCase {

    var manager: SimpleSwiftDataManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = try SimpleSwiftDataManager(inMemoryForTesting: true)
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Folder resolution

    func testSaveCreatesQuickNotesFolderOnFirstCall() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "Meeting prep", body: "Bring coffee")

        XCTAssertEqual(note.title, "Meeting prep")
        XCTAssertEqual(note.content, "Bring coffee")
        XCTAssertNotNil(note.folderID)

        // Folder ID was persisted
        let storedID = defaults.string(forKey: ThemeManager.quickNotesFolderIDKey)
        XCTAssertEqual(storedID, note.folderID?.uuidString)

        // Folder name is "Quick Notes"
        let folder = manager.folders.first(where: { $0.id == note.folderID })
        XCTAssertEqual(folder?.name, "Quick Notes")
    }

    func testSaveReusesExistingInboxFolder() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let first = service.save(title: "First", body: "1")
        let second = service.save(title: "Second", body: "2")

        XCTAssertEqual(first.folderID, second.folderID)
        XCTAssertEqual(manager.folders.filter { $0.name == "Quick Notes" }.count, 1)
    }

    func testSaveRecreatesFolderWhenStoredIDIsStale() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a stale folder ID that doesn't correspond to any real folder
        let staleID = UUID()
        defaults.set(staleID.uuidString, forKey: ThemeManager.quickNotesFolderIDKey)

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "Fresh", body: "body")

        XCTAssertNotNil(note.folderID)
        XCTAssertNotEqual(note.folderID, staleID)
        // Stored ID was replaced with the new folder's ID
        let newStored = defaults.string(forKey: ThemeManager.quickNotesFolderIDKey)
        XCTAssertEqual(newStored, note.folderID?.uuidString)
    }

    // MARK: - Title derivation

    func testEmptyTitleDerivesFromFirstNonEmptyLineOfBody() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "   ", body: "First line\nSecond line\nThird")
        XCTAssertEqual(note.title, "First line")
    }

    func testEmptyTitleSkipsLeadingBlankLines() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "", body: "\n\n  \nActual content")
        XCTAssertEqual(note.title, "Actual content")
    }

    func testEmptyTitleTruncatesLongFirstLineToSixtyChars() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let longLine = String(repeating: "a", count: 120)
        let note = service.save(title: "", body: longLine)

        XCTAssertEqual(note.title.count, 60)
        XCTAssertTrue(longLine.hasPrefix(note.title))
    }

    func testEmptyTitleAndEmptyBodyFallsBackToLiteralQuickNote() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "", body: "   \n  ")
        XCTAssertEqual(note.title, "Quick Note")
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "QuickNoteServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
