import XCTest
import SwiftData
@testable import Noty

@MainActor
final class SimpleSwiftDataManagerTests: XCTestCase {

    var manager: SimpleSwiftDataManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = try SimpleSwiftDataManager()
        try manager.clearAllData() // Start with clean slate
    }

    override func tearDown() async throws {
        try? manager.clearAllData()
        manager = nil
        try await super.tearDown()
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

    func testSearch() throws {
        // Add test notes
        _ = manager.addNote(title: "Swift Programming", content: "Learning SwiftUI", tags: ["swift", "programming"])
        _ = manager.addNote(title: "Cooking Recipe", content: "How to make pasta", tags: ["cooking", "recipe"])
        _ = manager.addNote(title: "Swift Tips", content: "Advanced Swift techniques", tags: ["swift", "advanced"])

        XCTAssertEqual(manager.notes.count, 3)

        // Test title search
        let swiftResults = manager.searchNotes(query: "Swift")
        XCTAssertEqual(swiftResults.count, 2)
        XCTAssertTrue(swiftResults.allSatisfy { $0.title.contains("Swift") || $0.content.contains("Swift") })

        // Test content search
        let cookingResults = manager.searchNotes(query: "pasta")
        XCTAssertEqual(cookingResults.count, 1)
        XCTAssertEqual(cookingResults.first?.title, "Cooking Recipe")

        // Test tag search
        let programmingResults = manager.searchNotes(query: "programming")
        XCTAssertEqual(programmingResults.count, 1)
        XCTAssertEqual(programmingResults.first?.title, "Swift Programming")

        // Test empty query
        let allResults = manager.searchNotes(query: "")
        XCTAssertEqual(allResults.count, 3)
    }

    func testMigrationFromJSON() async throws {
        // Create test JSON notes
        let jsonNotes = [
            Note(title: "JSON Note 1", content: "First note", tags: ["json", "test"]),
            Note(title: "JSON Note 2", content: "Second note", tags: ["json", "migration"]),
            Note(title: "Empty Note", content: "", tags: [])
        ]

        // Test migration
        try await manager.migrateFromJSON(jsonNotes)

        // Verify migration
        XCTAssertEqual(manager.notes.count, 3)

        let note1 = manager.notes.first { $0.title == "JSON Note 1" }
        XCTAssertNotNil(note1)
        XCTAssertEqual(note1?.content, "First note")
        XCTAssertEqual(Set(note1?.tags ?? []), Set(["json", "test"]))

        let note2 = manager.notes.first { $0.title == "JSON Note 2" }
        XCTAssertNotNil(note2)
        XCTAssertEqual(note2?.content, "Second note")
        XCTAssertEqual(Set(note2?.tags ?? []), Set(["json", "migration"]))

        let emptyNote = manager.notes.first { $0.title == "Empty Note" }
        XCTAssertNotNil(emptyNote)
        XCTAssertEqual(emptyNote?.content, "")
        XCTAssertEqual(emptyNote?.tags.count, 0)
    }

    func testPerformanceWithManyNotes() throws {
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

        // Test search performance
        measure {
            let results = manager.searchNotes(query: "Performance")
            XCTAssertEqual(results.count, noteCount)
        }
    }

    func testWebClipMigration() async throws {
        // Test note with webclip markup
        let webClipNote = Note(
            title: "Web Clip Test",
            content: "Check this out: [[webclip|Test Article|Great content|https://example.com]] More text here.",
            tags: ["webclip", "test"]
        )

        try await manager.migrateFromJSON([webClipNote])

        XCTAssertEqual(manager.notes.count, 1)

        let migratedNote = manager.notes.first!
        XCTAssertEqual(migratedNote.title, "Web Clip Test")

        // Content should be cleaned (webclip markup removed)
        XCTAssertFalse(migratedNote.content.contains("[[webclip"))
        XCTAssertTrue(migratedNote.content.contains("Check this out:"))
        XCTAssertTrue(migratedNote.content.contains("More text here."))
    }
}