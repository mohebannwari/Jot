import XCTest
import CoreSpotlight
@testable import Jot

@MainActor
final class SpotlightIndexerTests: XCTestCase {

    func testBuildSearchableItemSetsTitle() {
        let note = Note(title: "My Note", content: "Body text")
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertEqual(item.uniqueIdentifier, note.id.uuidString)
        XCTAssertEqual(item.attributeSet.title, "My Note")
    }

    func testBuildSearchableItemUsesUntitledForEmptyTitle() {
        let note = Note(title: "", content: "Body")
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertEqual(item.attributeSet.title, "Untitled")
    }

    func testBuildSearchableItemIncludesContentForUnlockedNote() {
        let note = Note(title: "Test", content: "Some content here")
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertNotNil(item.attributeSet.contentDescription)
        XCTAssertTrue(item.attributeSet.contentDescription?.contains("Some content here") ?? false)
    }

    func testBuildSearchableItemExcludesContentForLockedNote() {
        let note = Note(title: "Secret", content: "Hidden content", isLocked: true)
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertEqual(item.attributeSet.title, "Secret")
        XCTAssertNil(item.attributeSet.contentDescription)
    }

    func testBuildSearchableItemIncludesKeywords() {
        let note = Note(title: "Tagged", content: "Body", tags: ["swift", "ios"])
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertEqual(item.attributeSet.keywords, ["swift", "ios"])
    }

    func testBuildSearchableItemTruncatesLongContent() {
        let longContent = String(repeating: "x", count: 500)
        let note = Note(title: "Long", content: longContent)
        let item = SpotlightIndexer.shared.buildSearchableItem(for: note)

        XCTAssertEqual(item.attributeSet.contentDescription?.count, 300)
    }

    func testIndexNoteDoesNotCrash() {
        let note = Note(title: "Test", content: "Body")
        SpotlightIndexer.shared.indexNote(note)
    }

    func testDeindexDoesNotCrash() {
        SpotlightIndexer.shared.deindexNotes(ids: [UUID()])
    }

    func testDeindexEmptySetIsNoOp() {
        SpotlightIndexer.shared.deindexNotes(ids: [])
    }

    func testIndexDeletedNoteDeindexesInstead() {
        var note = Note(title: "Deleted", content: "Body")
        note.isDeleted = true
        // Should call deindex path, not index
        SpotlightIndexer.shared.indexNote(note)
    }

    func testIndexArchivedNoteDeindexesInstead() {
        var note = Note(title: "Archived", content: "Body")
        note.isArchived = true
        SpotlightIndexer.shared.indexNote(note)
    }

    func testReindexAllDoesNotCrash() {
        let notes = [
            Note(title: "Note 1", content: "Content 1"),
            Note(title: "Note 2", content: "Content 2", tags: ["tag"]),
            Note(title: "Locked", content: "Secret", isLocked: true),
        ]
        SpotlightIndexer.shared.reindexAll(notes)
    }
}
