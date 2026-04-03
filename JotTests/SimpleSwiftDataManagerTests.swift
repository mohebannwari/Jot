import XCTest
import SwiftData
@testable import Jot

@MainActor
final class SimpleSwiftDataManagerTests: XCTestCase {

    var manager: SimpleSwiftDataManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = try SimpleSwiftDataManager(inMemoryForTesting: true)
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    private func waitForReadiness(
        of manager: SimpleSwiftDataManager,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.hasLoadedInitialNotes && manager.hasCompletedMigrationCheck {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Manager readiness flags did not settle in time", file: file, line: line)
    }

    func testReadinessFlagsEventuallyBecomeTrue() async {
        await waitForReadiness(of: manager)
        XCTAssertTrue(manager.hasLoadedInitialNotes)
        XCTAssertTrue(manager.hasCompletedMigrationCheck)
    }

    func testReadinessCompletesWithEmptyStore() async throws {
        try manager.clearAllData()

        await waitForReadiness(of: manager)

        XCTAssertTrue(manager.notes.isEmpty)
        XCTAssertTrue(manager.hasLoadedInitialNotes)
        XCTAssertTrue(manager.hasCompletedMigrationCheck)
    }

    func testBasicCRUD() throws {
        // Test initial state
        XCTAssertEqual(manager.notes.count, 0)

        // Test adding a note
        let addedNote = manager.addNote(title: "Test Note", content: "Test content", tags: ["test"])
        XCTAssertEqual(manager.notes.count, 1)
        XCTAssertEqual(manager.notes.first?.title, "Test Note")
        XCTAssertEqual(manager.notes.first?.content, "Test content")
        XCTAssertEqual(manager.notes.first?.tags, ["test"])

        // Test updating a note
        var updatedNote = addedNote
        updatedNote.title = "Updated Title"
        updatedNote.content = "Updated content"
        updatedNote.tags = ["updated", "test"]

        manager.updateNote(updatedNote)
        XCTAssertEqual(manager.notes.count, 1)
        XCTAssertEqual(manager.notes.first?.title, "Updated Title")
        XCTAssertEqual(manager.notes.first?.content, "Updated content")
        XCTAssertEqual(Set(manager.notes.first?.tags ?? []), Set(["updated", "test"]))

        // Test deleting a note
        manager.deleteNote(id: addedNote.id)
        XCTAssertEqual(manager.notes.count, 0)
    }

    func testSearch() async throws {
        // Add test notes
        _ = manager.addNote(title: "Swift Programming", content: "Learning SwiftUI", tags: ["swift", "programming"])
        _ = manager.addNote(title: "Cooking Recipe", content: "How to make pasta", tags: ["cooking", "recipe"])
        _ = manager.addNote(title: "Swift Tips", content: "Advanced Swift techniques", tags: ["swift", "advanced"])

        XCTAssertEqual(manager.notes.count, 3)

        // Test title search
        let swiftResults = await manager.searchNotes(query: "Swift")
        XCTAssertEqual(swiftResults.count, 2)
        XCTAssertTrue(swiftResults.allSatisfy { $0.title.contains("Swift") || $0.content.contains("Swift") })

        // Test content search
        let cookingResults = await manager.searchNotes(query: "pasta")
        XCTAssertEqual(cookingResults.count, 1)
        XCTAssertEqual(cookingResults.first?.title, "Cooking Recipe")

        // Test tag search
        let programmingResults = await manager.searchNotes(query: "programming")
        XCTAssertEqual(programmingResults.count, 1)
        XCTAssertEqual(programmingResults.first?.title, "Swift Programming")

        // Test empty query
        let allResults = await manager.searchNotes(query: "")
        XCTAssertEqual(allResults.count, 3)
    }

    // testMigrationFromJSON removed -- migrateFromJSON no longer exists on SimpleSwiftDataManager

    func testPerformanceWithManyNotes() async throws {
        let noteCount = 1000

        // Test adding performance
        measure {
            for i in 0..<noteCount {
                _ = manager.addNote(
                    title: "Performance Note \(i)",
                    content: "Content for note \(i)",
                    tags: ["performance", "test", "batch_\(i % 10)"]
                )
            }
        }

        XCTAssertEqual(manager.notes.count, noteCount)

        let results = await manager.searchNotes(query: "Performance", limit: noteCount + 10)
        XCTAssertEqual(results.count, noteCount)
    }

    // testWebClipMigration removed -- migrateFromJSON no longer exists on SimpleSwiftDataManager

    func testCreateFolderPersistsAndIsOrderedNewestFirst() throws {
        let firstFolder = manager.createFolder(name: "Folder A")
        XCTAssertNotNil(firstFolder)

        let secondFolder = manager.createFolder(name: "Folder B")
        XCTAssertNotNil(secondFolder)

        XCTAssertEqual(manager.folders.count, 2)
        XCTAssertEqual(manager.folders.first?.name, "Folder B")
        XCTAssertEqual(manager.folders.last?.name, "Folder A")

        // Cross-instance persistence requires a real on-disk store; covered by integration tests.
    }

    func testCreateFolderWithNoteMovesNoteAndClearsPin() {
        let note = manager.addNote(title: "Pinned Note", content: "Body")
        manager.togglePin(id: note.id)

        let folder = manager.createFolder(withNoteID: note.id, name: "Inbox")
        XCTAssertNotNil(folder)

        guard let folder else {
            XCTFail("Expected folder to be created")
            return
        }

        guard let moved = manager.notes.first(where: { $0.id == note.id }) else {
            XCTFail("Expected moved note to exist")
            return
        }

        XCTAssertEqual(moved.folderID, folder.id)
        XCTAssertFalse(moved.isPinned)
    }

    func testMoveNoteIntoAndOutOfFolder() {
        let note = manager.addNote(title: "Move Me", content: "Body")
        let folder = manager.createFolder(name: "Projects")

        guard let folder else {
            XCTFail("Expected folder to be created")
            return
        }

        XCTAssertTrue(manager.moveNote(id: note.id, toFolderID: folder.id))
        XCTAssertEqual(manager.notes.first(where: { $0.id == note.id })?.folderID, folder.id)

        XCTAssertTrue(manager.moveNote(id: note.id, toFolderID: nil))
        XCTAssertNil(manager.notes.first(where: { $0.id == note.id })?.folderID)
    }

    func testDeleteNotesDeletesOnlyRequestedSet() {
        let keep = manager.addNote(title: "Keep", content: "Body")
        let deleteA = manager.addNote(title: "Delete A", content: "Body")
        let deleteB = manager.addNote(title: "Delete B", content: "Body")

        let deletedCount = manager.deleteNotes(ids: [deleteA.id, deleteB.id])

        XCTAssertEqual(deletedCount, 2)
        XCTAssertEqual(manager.notes.count, 1)
        XCTAssertEqual(manager.notes.first?.id, keep.id)
    }

    func testMoveNotesMovesSetAndClearsPins() {
        let first = manager.addNote(title: "First", content: "Body")
        let second = manager.addNote(title: "Second", content: "Body")
        _ = manager.addNote(title: "Third", content: "Body")
        manager.togglePin(id: first.id)
        manager.togglePin(id: second.id)

        let folder = manager.createFolder(name: "Batch Folder")
        XCTAssertNotNil(folder)

        guard let folder else {
            XCTFail("Expected folder to be created")
            return
        }

        let movedCount = manager.moveNotes(ids: [first.id, second.id], toFolderID: folder.id)

        XCTAssertEqual(movedCount, 2)
        XCTAssertEqual(manager.notes.first(where: { $0.id == first.id })?.folderID, folder.id)
        XCTAssertEqual(manager.notes.first(where: { $0.id == second.id })?.folderID, folder.id)
        XCTAssertFalse(manager.notes.first(where: { $0.id == first.id })?.isPinned ?? true)
        XCTAssertFalse(manager.notes.first(where: { $0.id == second.id })?.isPinned ?? true)
    }

    func testDeleteFolderUnfilesContainedNotes() {
        let note1 = manager.addNote(title: "One", content: "Body")
        let note2 = manager.addNote(title: "Two", content: "Body")
        let folder = manager.createFolder(name: "Archive")

        guard let folder else {
            XCTFail("Expected folder to be created")
            return
        }

        XCTAssertTrue(manager.moveNote(id: note1.id, toFolderID: folder.id))
        XCTAssertTrue(manager.moveNote(id: note2.id, toFolderID: folder.id))

        manager.deleteFolder(id: folder.id)

        XCTAssertFalse(manager.folders.contains(where: { $0.id == folder.id }))
        XCTAssertNil(manager.notes.first(where: { $0.id == note1.id })?.folderID)
        XCTAssertNil(manager.notes.first(where: { $0.id == note2.id })?.folderID)
    }

    func testNoteEntityRoundTripPreservesFolderID() {
        let folderID = UUID()
        let note = Note(
            title: "Foldered",
            content: "Body",
            tags: ["a"],
            isPinned: false,
            folderID: folderID
        )
        let entity = NoteEntity(from: note)
        let converted = entity.toNote()

        XCTAssertEqual(converted.folderID, folderID)
    }

    func testFolderEntityRoundTripPreservesFields() {
        let folder = Folder(name: "Design", createdAt: Date(), modifiedAt: Date())
        let entity = FolderEntity(from: folder)
        let converted = entity.toFolder()

        XCTAssertEqual(converted.id, folder.id)
        XCTAssertEqual(converted.name, folder.name)
        XCTAssertEqual(converted.createdAt, folder.createdAt)
        XCTAssertEqual(converted.modifiedAt, folder.modifiedAt)
    }
}
