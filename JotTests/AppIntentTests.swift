import XCTest
@testable import Jot

@MainActor
final class AppIntentTests: XCTestCase {

    var manager: SimpleSwiftDataManager!

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
}
