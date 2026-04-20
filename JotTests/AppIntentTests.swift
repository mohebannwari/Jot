import XCTest
@testable import Jot

@MainActor
final class AppIntentTests: XCTestCase {

    var manager: SimpleSwiftDataManager!

    private func makeLockedNote(
        title: String = "Locked Note",
        content: String = "Secret"
    ) throws -> Note {
        let note = manager.addNote(title: title, content: content)
        manager.toggleLock(id: note.id)

        let lockedNote = try XCTUnwrap(manager.notes.first(where: { $0.id == note.id }))
        XCTAssertTrue(lockedNote.isLocked)
        return lockedNote
    }

    override func setUp() async throws {
        try await super.setUp()
        manager = try SimpleSwiftDataManager(inMemoryForTesting: true)
        SimpleSwiftDataManager.shared = manager
    }

    override func tearDown() async throws {
        SimpleSwiftDataManager.shared = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Entity Construction

    func testNoteAppEntityFromNote() {
        let note = Note(title: "Test Note", content: "Hello")
        let entity = NoteAppEntity(from: note)

        XCTAssertEqual(entity.id, note.id)
        XCTAssertEqual(entity.title, "Test Note")
    }

    func testNoteAppEntityUntitledFallback() {
        let note = Note(title: "", content: "Body only")
        let entity = NoteAppEntity(from: note)

        XCTAssertEqual(entity.title, "Untitled")
    }

    func testFolderAppEntityFromFolder() {
        let folder = Folder(name: "Work")
        let entity = FolderAppEntity(from: folder)

        XCTAssertEqual(entity.id, folder.id)
        XCTAssertEqual(entity.name, "Work")
    }

    // MARK: - CreateNoteIntent

    func testCreateNoteIntentPerform() async throws {
        var intent = CreateNoteIntent()
        intent.noteTitle = "Siri Note"
        intent.content = "Created via Shortcuts"

        let result = try await intent.perform()
        let entity = result.value

        XCTAssertEqual(entity?.title, "Siri Note")
        XCTAssertTrue(manager.notes.contains(where: { $0.title == "Siri Note" }))
    }

    // MARK: - AppendToNoteIntent

    func testAppendToNoteIntentPerform() async throws {
        let note = manager.addNote(title: "Base Note", content: "Original")

        var intent = AppendToNoteIntent()
        intent.note = NoteAppEntity(from: note)
        intent.text = "Appended"

        _ = try await intent.perform()

        guard let updated = manager.notes.first(where: { $0.id == note.id }) else {
            XCTFail("Note not found after append")
            return
        }
        XCTAssertTrue(updated.content.contains("Appended"))
    }

    // MARK: - NoteQuery

    func testNoteQueryEntitiesForExcludesLockedNotes() async throws {
        let unlocked = manager.addNote(title: "Unlocked", content: "Visible")
        let locked = try makeLockedNote()

        let entities = try await NoteQuery().entities(for: [unlocked.id, locked.id])

        XCTAssertEqual(entities.map(\.id), [unlocked.id])
    }

    func testNoteQueryEntitiesMatchingExcludesLockedNotes() async throws {
        _ = manager.addNote(title: "Trip Plan", content: "Visible match")
        _ = try makeLockedNote(title: "Trip Secret", content: "Hidden match")

        let entities = try await NoteQuery().entities(matching: "Trip")

        XCTAssertEqual(entities.map(\.title), ["Trip Plan"])
    }

    func testNoteQuerySuggestedEntitiesExcludesLockedNotesBeforeApplyingLimit() async throws {
        var unlockedIDs: [UUID] = []
        for index in 0..<10 {
            let note = manager.addNote(title: "Unlocked \(index)", content: "Visible")
            unlockedIDs.append(note.id)
        }
        let locked = try makeLockedNote(title: "Newest Locked", content: "Hidden")

        let suggestions = try await NoteQuery().suggestedEntities()

        XCTAssertEqual(suggestions.count, 10)
        XCTAssertFalse(suggestions.contains(where: { $0.id == locked.id }))
        XCTAssertEqual(Set(suggestions.map(\.id)), Set(unlockedIDs))
    }

    func testAppendToNoteIntentPerformThrowsForLockedNote() async throws {
        let locked = try makeLockedNote(title: "Locked Target", content: "Original")

        var intent = AppendToNoteIntent()
        intent.note = NoteAppEntity(from: locked)
        intent.text = "Appended"

        do {
            _ = try await intent.perform()
            XCTFail("Expected appending to a locked note to fail")
        } catch let error as IntentError {
            XCTAssertEqual(error, .noteLocked)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let unchanged = try XCTUnwrap(manager.notes.first(where: { $0.id == locked.id }))
        XCTAssertEqual(unchanged.content, "Original")
    }
}
