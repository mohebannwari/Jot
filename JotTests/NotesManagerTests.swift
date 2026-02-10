import XCTest
@testable import Jot

final class NotesManagerTests: XCTestCase {
    @MainActor
    func testAddUpdateDeleteAndPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("notes.json")

        // Start empty (no seeding)
        let manager = NotesManager(storageURL: url, seedIfEmpty: false)
        XCTAssertEqual(manager.notes.count, 0)

        // Add
        let created = manager.addNote(title: "Test", content: "Body", tags: ["tag"]) 
        XCTAssertEqual(manager.notes.count, 1)
        XCTAssertEqual(manager.notes.first?.id, created.id)

        // Update
        var updated = created
        updated.title = "Updated"
        manager.updateNote(updated)
        XCTAssertEqual(manager.notes.first?.title, "Updated")

        // Reload from disk
        let reloaded = NotesManager(storageURL: url, seedIfEmpty: false)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.title, "Updated")

        // Delete
        reloaded.deleteNote(id: updated.id)
        XCTAssertEqual(reloaded.notes.count, 0)
    }
}

