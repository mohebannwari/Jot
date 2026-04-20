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
        SpotlightIndexer.shared.onIndexNoteForTesting = nil
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

        // Test updating a note. Title/content go through updateNote, tags go
        // through updateTags — updateNote intentionally preserves existing
        // entity tags so autosaves from the editor can't clobber tags the user
        // edited in the properties panel with a stale snapshot.
        var updatedNote = addedNote
        updatedNote.title = "Updated Title"
        updatedNote.content = "Updated content"

        manager.updateNote(updatedNote)
        manager.updateTags(id: addedNote.id, tags: ["updated", "test"])
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

        // Multi-word tag names: first fetch token matches "test", post-filter must require both words in tags/title/body.
        _ = manager.addNote(
            title: "Metadata Only",
            content: "Body has neither token alone in a misleading way.",
            tags: ["test tag"])
        let multiWordTagResults = await manager.searchNotes(query: "test tag")
        XCTAssertTrue(multiWordTagResults.contains { $0.title == "Metadata Only" })

        // Test empty query
        let allResults = await manager.searchNotes(query: "")
        XCTAssertEqual(allResults.count, 4)
    }

    // testMigrationFromJSON removed -- migrateFromJSON no longer exists on SimpleSwiftDataManager

    func testPerformanceWithManyNotes() async throws {
        let noteCount = 1000

        // XCTest `measure` runs this block multiple times (10 by default), so
        // every iteration must start from a clean store — otherwise we'd be
        // measuring "add 1000 notes to an increasingly full store" and the
        // post-measure assertions would see 10x the expected count.
        measure {
            try? manager.clearAllData()
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

    func testAllNotesForBackupIncludesArchivedAndDeletedNotesBeyondSidebarCap() throws {
        let active = manager.addNote(title: "Active", content: "Body")

        var archivedIDs = Set<UUID>()
        for index in 0..<505 {
            archivedIDs.insert(manager.addNote(title: "Archived \(index)", content: "Body").id)
        }
        XCTAssertEqual(manager.archiveNotes(ids: archivedIDs), 505)

        var deletedIDs = Set<UUID>()
        for index in 0..<506 {
            deletedIDs.insert(manager.addNote(title: "Deleted \(index)", content: "Body").id)
        }
        XCTAssertEqual(manager.moveToTrash(ids: deletedIDs), 506)

        let activeFolder = manager.createFolder(name: "Projects")
        let archivedFolder = manager.createFolder(name: "Archive Me")
        XCTAssertNotNil(activeFolder)
        XCTAssertNotNil(archivedFolder)
        if let archivedFolder {
            manager.archiveFolder(archivedFolder)
        }

        let snapshot = try BackupManager.shared.backupSnapshot(from: manager)

        XCTAssertEqual(snapshot.notes.count, 1 + 505 + 506)
        XCTAssertEqual(snapshot.notes.filter(\.isArchived).count, 505)
        XCTAssertTrue(snapshot.notes.contains(where: { $0.id == active.id }))
        XCTAssertEqual(snapshot.notes.filter { deletedIDs.contains($0.id) }.count, 506)
        XCTAssertTrue(snapshot.folders.contains(where: { $0.name == activeFolder?.name }))
        XCTAssertTrue(snapshot.folders.contains(where: { $0.name == archivedFolder?.name && $0.isArchived }))

        XCTAssertEqual(manager.archivedNotes.count, 500)
        XCTAssertEqual(manager.deletedNotes.count, 500)
    }

    func testPersistentInitPreservesPerformanceNoteTitles() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleSwiftDataManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        let storeURL = storeDirectory.appendingPathComponent("JotTests.store")

        var firstLaunchManager: SimpleSwiftDataManager? = try SimpleSwiftDataManager(
            storeURLForTesting: storeURL
        )
        guard let createdManager = firstLaunchManager else {
            XCTFail("Expected first persistent manager")
            return
        }
        await waitForReadiness(of: createdManager)

        let note = createdManager.addNote(
            title: "Performance Note Legitimate User Content",
            content: "Keep this note"
        )
        firstLaunchManager = nil

        let relaunchedManager = try SimpleSwiftDataManager(storeURLForTesting: storeURL)
        await waitForReadiness(of: relaunchedManager)

        let persisted = try XCTUnwrap(relaunchedManager.notes.first(where: { $0.id == note.id }))
        XCTAssertEqual(persisted.title, "Performance Note Legitimate User Content")
        XCTAssertEqual(persisted.content, "Keep this note")
    }

    func testToggleLockReindexesSpotlightWithUpdatedPrivacyState() throws {
        let note = manager.addNote(title: "Secret", content: "Private body")
        var indexedNotes: [Note] = []
        SpotlightIndexer.shared.onIndexNoteForTesting = { indexedNotes.append($0) }

        manager.toggleLock(id: note.id)
        manager.toggleLock(id: note.id)

        XCTAssertEqual(indexedNotes.count, 2)

        let locked = indexedNotes[0]
        XCTAssertTrue(locked.isLocked)
        XCTAssertNil(SpotlightIndexer.shared.buildSearchableItem(for: locked).attributeSet.contentDescription)

        let unlocked = indexedNotes[1]
        XCTAssertFalse(unlocked.isLocked)
        XCTAssertEqual(
            SpotlightIndexer.shared.buildSearchableItem(for: unlocked).attributeSet.contentDescription,
            "Private body"
        )
    }
}
