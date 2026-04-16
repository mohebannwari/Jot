import XCTest
@testable import Jot

/// `RootQuickActionKeywordCatalog` backs the unified command-palette filter in `FloatingSearch`.
/// These tests guard against a regression where PR #22's refactor dropped keyword aliases:
/// before the fix, typing "Capture" failed to match "Floating Note" because the spec filter
/// compared against `spec.title.localizedCaseInsensitiveContains(q)` instead of the alias list.
final class RootQuickActionKeywordCatalogTests: XCTestCase {

    // MARK: - Alias matching (the original bug)

    /// "Quick Capture" is an alias for index 1 (Floating Note). Must match.
    func testMatches_CaptureAliasesOntoFloatingNote() {
        let catalog = defaultCatalog()
        XCTAssertTrue(catalog.matches(index: 1, query: "capture"),
            "'capture' should match 'Floating Note' via the 'Quick Capture' alias")
        XCTAssertTrue(catalog.matches(index: 1, query: "Quick"),
            "'quick' should match 'Floating Note' via the 'Quick Note' / 'Quick Capture' aliases")
        XCTAssertTrue(catalog.matches(index: 1, query: "panel"),
            "'panel' should match 'Floating Note' via the 'Floating Panel' alias")
    }

    /// "Preferences" is a macOS-convention alias for Settings (index 8).
    func testMatches_PreferencesAliasesOntoSettings() {
        let catalog = defaultCatalog()
        XCTAssertTrue(catalog.matches(index: 8, query: "preferences"))
        XCTAssertTrue(catalog.matches(index: 8, query: "Pref"))
    }

    /// Meeting (index 2) has "Meeting", "Recording", "Session" aliases.
    func testMatches_MeetingAliases() {
        let catalog = defaultCatalog()
        XCTAssertTrue(catalog.matches(index: 2, query: "recording"))
        XCTAssertTrue(catalog.matches(index: 2, query: "session"))
    }

    /// Case- and diacritic-insensitive matching — standard Foundation semantics.
    func testMatches_IsCaseInsensitive() {
        let catalog = defaultCatalog()
        XCTAssertTrue(catalog.matches(index: 0, query: "NEW"))
        XCTAssertTrue(catalog.matches(index: 0, query: "nOtE"))
    }

    /// Empty / whitespace queries never match — avoids returning every command for a no-op query.
    func testMatches_EmptyQueryReturnsFalse() {
        let catalog = defaultCatalog()
        for idx in 0...8 {
            XCTAssertFalse(catalog.matches(index: idx, query: ""),
                "Empty query must never match (index \(idx))")
            XCTAssertFalse(catalog.matches(index: idx, query: "   "),
                "Whitespace-only query must never match (index \(idx))")
        }
    }

    /// Out-of-range indices return no keywords — defensive guard.
    func testKeywords_OutOfRangeReturnsEmpty() {
        let catalog = defaultCatalog()
        XCTAssertEqual(catalog.keywords(for: -1), [])
        XCTAssertEqual(catalog.keywords(for: 99), [])
    }

    // MARK: - State-dependent indices

    /// Index 5 switches label between "Pin Note" and "Unpin Note" based on pin state;
    /// both "pin" and "unpin" aliases always present, so either verb always matches.
    func testPinIndex_FlipsLabelByState() {
        let pinned = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: true,
            isZenMode: false,
            archiveOrRestoreTitle: "Archive")
        XCTAssertTrue(pinned.keywords(for: 5).contains("Unpin Note"))
        XCTAssertFalse(pinned.keywords(for: 5).contains("Pin Note"))

        let unpinned = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: false,
            archiveOrRestoreTitle: "Archive")
        XCTAssertTrue(unpinned.keywords(for: 5).contains("Pin Note"))
        XCTAssertFalse(unpinned.keywords(for: 5).contains("Unpin Note"))

        // Alias matching should work regardless of pin state.
        XCTAssertTrue(pinned.matches(index: 5, query: "pin"))
        XCTAssertTrue(unpinned.matches(index: 5, query: "unpin"))
    }

    /// Index 6 switches label between "Zen Mode" and "Exit Zen Mode" based on zen state.
    func testZenIndex_FlipsLabelByState() {
        let zen = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: true,
            archiveOrRestoreTitle: "Archive")
        XCTAssertTrue(zen.keywords(for: 6).contains("Exit Zen Mode"))

        let notZen = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: false,
            archiveOrRestoreTitle: "Archive")
        XCTAssertTrue(notZen.keywords(for: 6).contains("Zen Mode"))
        XCTAssertTrue(notZen.matches(index: 6, query: "focus"),
            "'focus' alias matches zen-mode index regardless of state")
    }

    /// Index 7 uses the dynamic archive/restore title. Aliases "Archive" and "Restore"
    /// always match so either verb works.
    func testArchiveIndex_UsesDynamicTitle() {
        let archive = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: false,
            archiveOrRestoreTitle: "Archive Note")
        XCTAssertTrue(archive.keywords(for: 7).contains("Archive Note"))
        XCTAssertTrue(archive.matches(index: 7, query: "restore"),
            "'restore' alias matches even when current dynamic title is 'Archive Note'")

        let restore = RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: false,
            archiveOrRestoreTitle: "Restore Note")
        XCTAssertTrue(restore.keywords(for: 7).contains("Restore Note"))
        XCTAssertTrue(restore.matches(index: 7, query: "archive"))
    }

    // MARK: - Helpers

    private func defaultCatalog() -> RootQuickActionKeywordCatalog {
        RootQuickActionKeywordCatalog(
            selectedNoteIsPinned: false,
            isZenMode: false,
            archiveOrRestoreTitle: "Archive")
    }
}
