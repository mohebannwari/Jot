import XCTest
@testable import Jot

final class NoteSelectionPolicyTests: XCTestCase {
    func testResolvePrefersCurrentActiveNoteWhenStillPresent() {
        var first = Note(title: "First", content: "")
        var second = Note(title: "Second", content: "")
        first.date = Date(timeIntervalSince1970: 100)
        second.date = Date(timeIntervalSince1970: 200)

        let resolved = NoteSelectionPolicy.resolveActiveNote(
            notes: [second, first],
            currentActiveID: first.id,
            selectedNoteIDs: [second.id],
            selectionAnchorID: second.id
        )

        XCTAssertEqual(resolved?.id, first.id)
    }

    func testResolveFallsBackToAnchorSelection() {
        var first = Note(title: "First", content: "")
        var second = Note(title: "Second", content: "")
        first.date = Date(timeIntervalSince1970: 100)
        second.date = Date(timeIntervalSince1970: 200)

        let resolved = NoteSelectionPolicy.resolveActiveNote(
            notes: [second, first],
            currentActiveID: UUID(),
            selectedNoteIDs: [first.id, second.id],
            selectionAnchorID: first.id
        )

        XCTAssertEqual(resolved?.id, first.id)
    }

    func testResolveFallsBackToSelectedNoteWhenAnchorMissing() {
        var first = Note(title: "First", content: "")
        var second = Note(title: "Second", content: "")
        first.date = Date(timeIntervalSince1970: 100)
        second.date = Date(timeIntervalSince1970: 200)

        let resolved = NoteSelectionPolicy.resolveActiveNote(
            notes: [second, first],
            currentActiveID: UUID(),
            selectedNoteIDs: [first.id],
            selectionAnchorID: UUID()
        )

        XCTAssertEqual(resolved?.id, first.id)
    }

    func testResolveFallsBackToLatestEditedNoteWhenNoSelection() {
        var older = Note(title: "Older", content: "")
        var newer = Note(title: "Newer", content: "")
        older.date = Date(timeIntervalSince1970: 100)
        newer.date = Date(timeIntervalSince1970: 200)

        let resolved = NoteSelectionPolicy.resolveActiveNote(
            notes: [older, newer],
            currentActiveID: nil,
            selectedNoteIDs: [],
            selectionAnchorID: nil
        )

        XCTAssertEqual(resolved?.id, newer.id)
    }
}
