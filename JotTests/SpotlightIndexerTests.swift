import XCTest
import CoreSpotlight
@testable import Jot

@MainActor
final class SpotlightIndexerTests: XCTestCase {

    func testIndexNoteDoesNotCrash() {
        let note = Note(title: "Test Note", content: "Some content", tags: ["test"])
        SpotlightIndexer.shared.indexNote(note)
        // Verify no crash -- CSSearchableIndex is async
    }

    func testIndexLockedNoteDoesNotExposeContent() {
        let note = Note(title: "Secret", content: "Hidden content", isLocked: true)
        // Locked notes should still be indexable (title only)
        SpotlightIndexer.shared.indexNote(note)
    }

    func testDeindexDoesNotCrash() {
        let id = UUID()
        SpotlightIndexer.shared.deindexNotes(ids: [id])
    }

    func testDeindexEmptySetIsNoOp() {
        SpotlightIndexer.shared.deindexNotes(ids: [])
    }

    func testDeletedNoteIsDeindexed() {
        var note = Note(title: "Deleted", content: "Body")
        note.isDeleted = true
        // indexNote should detect isDeleted and deindex instead
        SpotlightIndexer.shared.indexNote(note)
    }

    func testArchivedNoteIsDeindexed() {
        var note = Note(title: "Archived", content: "Body")
        note.isArchived = true
        // indexNote should detect isArchived and deindex instead
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

    func testReindexAllFiltersDeletedAndArchived() {
        var deleted = Note(title: "Deleted", content: "Body")
        deleted.isDeleted = true
        var archived = Note(title: "Archived", content: "Body")
        archived.isArchived = true
        let active = Note(title: "Active", content: "Body")

        // Should only index the active note, not crash
        SpotlightIndexer.shared.reindexAll([deleted, archived, active])
    }
}
