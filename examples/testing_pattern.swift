//
//  testing_pattern.swift
//  Noty Examples
//
//  Simplified pattern extracted from: NotyTests/NotesManagerTests.swift
//
//  This demonstrates the testing patterns and best practices for
//  unit testing in the Noty app using XCTest.
//

import XCTest
@testable import Noty

// MARK: - Testing Pattern

/// Example test class following Noty's established patterns:
/// - Named {FeatureName}Tests.swift
/// - Tests marked with @MainActor for async code
/// - Temporary storage for isolation
/// - Arrange-Act-Assert pattern
/// - Proper cleanup
final class ExampleFeatureTests: XCTestCase {
    
    // MARK: - Test Properties
    // Properties needed across multiple tests
    var tempDirectory: URL!
    var storageURL: URL!
    
    // MARK: - Setup & Teardown
    
    /// Set up before each test
    /// Creates isolated temporary storage
    override func setUp() {
        super.setUp()
        
        // Create unique temporary directory for this test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(
                at: tempDirectory,
                withIntermediateDirectories: true
            )
            storageURL = tempDirectory.appendingPathComponent("test_data.json")
        } catch {
            XCTFail("Failed to create temp directory: \(error)")
        }
    }
    
    /// Clean up after each test
    /// Removes temporary files
    override func tearDown() {
        // Remove temp directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        super.tearDown()
    }
    
    // MARK: - CRUD Tests
    
    /// Test adding an item
    /// Verifies count increases and data is correct
    @MainActor
    func testAddItem() throws {
        // Arrange: Create manager with empty storage
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        XCTAssertEqual(manager.items.count, 0, "Should start with empty storage")
        
        // Act: Add an item
        let created = manager.addItem(title: "Test Title", content: "Test Content")
        
        // Assert: Verify item was added
        XCTAssertEqual(manager.items.count, 1, "Should have 1 item after adding")
        XCTAssertEqual(manager.items.first?.id, created.id, "Item ID should match")
        XCTAssertEqual(manager.items.first?.title, "Test Title", "Title should match")
        XCTAssertEqual(manager.items.first?.content, "Test Content", "Content should match")
    }
    
    /// Test updating an existing item
    /// Verifies changes are persisted
    @MainActor
    func testUpdateItem() throws {
        // Arrange: Create manager and add initial item
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let created = manager.addItem(title: "Original", content: "Original Content")
        
        // Act: Update the item
        var updated = created
        updated.title = "Updated"
        updated.content = "Updated Content"
        manager.updateItem(updated)
        
        // Assert: Verify update
        XCTAssertEqual(manager.items.count, 1, "Should still have 1 item")
        XCTAssertEqual(manager.items.first?.title, "Updated", "Title should be updated")
        XCTAssertEqual(manager.items.first?.content, "Updated Content", "Content should be updated")
    }
    
    /// Test deleting an item
    /// Verifies item is removed from storage
    @MainActor
    func testDeleteItem() throws {
        // Arrange: Create manager with items
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let item1 = manager.addItem(title: "Item 1", content: "Content 1")
        let item2 = manager.addItem(title: "Item 2", content: "Content 2")
        XCTAssertEqual(manager.items.count, 2, "Should have 2 items")
        
        // Act: Delete first item
        manager.deleteItem(id: item1.id)
        
        // Assert: Verify deletion
        XCTAssertEqual(manager.items.count, 1, "Should have 1 item after deletion")
        XCTAssertEqual(manager.items.first?.id, item2.id, "Remaining item should be item2")
        XCTAssertNil(manager.items.first(where: { $0.id == item1.id }), "Deleted item should not exist")
    }
    
    // MARK: - Persistence Tests
    
    /// Test data persistence
    /// Verifies data survives reload
    @MainActor
    func testPersistence() throws {
        // Arrange & Act: Create manager, add item, then reload
        let manager1 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let created = manager1.addItem(title: "Persistent", content: "This should persist")
        
        // Create new manager instance (simulates app restart)
        let manager2 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        
        // Assert: Data should be loaded from disk
        XCTAssertEqual(manager2.items.count, 1, "Should load 1 item from disk")
        XCTAssertEqual(manager2.items.first?.id, created.id, "Loaded item ID should match")
        XCTAssertEqual(manager2.items.first?.title, "Persistent", "Loaded title should match")
        XCTAssertEqual(manager2.items.first?.content, "This should persist", "Loaded content should match")
    }
    
    /// Test persistence after update
    /// Verifies updates are saved to disk
    @MainActor
    func testUpdatePersistence() throws {
        // Arrange: Create item and update it
        let manager1 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let created = manager1.addItem(title: "Original", content: "Original")
        
        var updated = created
        updated.title = "Updated"
        manager1.updateItem(updated)
        
        // Act: Reload from disk
        let manager2 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        
        // Assert: Updated data should be persisted
        XCTAssertEqual(manager2.items.first?.title, "Updated", "Updated title should persist")
    }
    
    /// Test persistence after delete
    /// Verifies deletions are saved to disk
    @MainActor
    func testDeletePersistence() throws {
        // Arrange: Create items and delete one
        let manager1 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let item1 = manager1.addItem(title: "Item 1", content: "Content 1")
        let item2 = manager1.addItem(title: "Item 2", content: "Content 2")
        manager1.deleteItem(id: item1.id)
        
        // Act: Reload from disk
        let manager2 = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        
        // Assert: Only remaining item should be loaded
        XCTAssertEqual(manager2.items.count, 1, "Should load 1 item after deletion")
        XCTAssertEqual(manager2.items.first?.id, item2.id, "Loaded item should be item2")
    }
    
    // MARK: - Edge Case Tests
    
    /// Test empty state handling
    /// Verifies manager works with no data
    @MainActor
    func testEmptyState() throws {
        // Arrange & Act
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        
        // Assert
        XCTAssertEqual(manager.items.count, 0, "Should start empty")
        XCTAssertTrue(manager.items.isEmpty, "Items array should be empty")
    }
    
    /// Test updating non-existent item
    /// Verifies graceful handling of invalid updates
    @MainActor
    func testUpdateNonExistentItem() throws {
        // Arrange
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        let fakeItem = ExampleItem(title: "Fake", content: "Doesn't exist")
        
        // Act
        manager.updateItem(fakeItem)
        
        // Assert: Should not crash, items should remain empty
        XCTAssertEqual(manager.items.count, 0, "Should not add non-existent item")
    }
    
    /// Test deleting non-existent item
    /// Verifies graceful handling of invalid deletes
    @MainActor
    func testDeleteNonExistentItem() throws {
        // Arrange
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        manager.addItem(title: "Real Item", content: "Content")
        
        // Act
        manager.deleteItem(id: UUID()) // Random UUID
        
        // Assert: Should not crash, real item should remain
        XCTAssertEqual(manager.items.count, 1, "Real item should remain")
    }
    
    // MARK: - Performance Tests
    
    /// Test performance of adding many items
    /// Verifies acceptable performance with larger datasets
    @MainActor
    func testAddPerformance() throws {
        let manager = ExampleManager(storageURL: storageURL, seedIfEmpty: false)
        
        measure {
            // Add 100 items
            for i in 0..<100 {
                manager.addItem(title: "Item \(i)", content: "Content \(i)")
            }
        }
    }
}

// MARK: - Key Takeaways

/*
 Testing Patterns:
 
 1. TEST CLASS STRUCTURE
    - Name: {FeatureName}Tests.swift
    - Inherit from XCTestCase
    - Mark as final
    - Use @MainActor for async code
 
 2. TEST METHOD NAMING
    - Start with 'test'
    - Descriptive name: testAddItem, testDeletePersistence
    - One test per behavior
    - Group related tests with MARK comments
 
 3. ARRANGE-ACT-ASSERT PATTERN
    // Arrange: Set up test conditions
    let manager = ExampleManager(...)
    
    // Act: Perform the action
    let result = manager.addItem(...)
    
    // Assert: Verify expected outcome
    XCTAssertEqual(result, expected)
 
 4. ISOLATION WITH TEMPORARY STORAGE
    - Create unique temp directory per test
    - Use UUID for uniqueness
    - Clean up in tearDown()
    - Prevents test interference
 
 5. SETUP & TEARDOWN
    override func setUp() {
        // Create temp storage
        // Initialize test data
    }
    
    override func tearDown() {
        // Clean up temp files
        // Reset state
    }
 
 6. COMMON ASSERTIONS
    XCTAssertEqual(a, b)              // Values equal
    XCTAssertNotEqual(a, b)           // Values not equal
    XCTAssertTrue(condition)          // Condition is true
    XCTAssertFalse(condition)         // Condition is false
    XCTAssertNil(value)               // Value is nil
    XCTAssertNotNil(value)            // Value is not nil
    XCTAssertThrowsError(try expr)    // Expression throws
    XCTFail("Message")                // Force failure
 
 7. TESTING MANAGERS
    - Inject custom storageURL
    - Disable seeding: seedIfEmpty: false
    - Test CRUD operations
    - Test persistence by reloading
    - Test edge cases
 
 8. PERSISTENCE TESTING
    1. Create manager instance
    2. Perform operations
    3. Create new manager instance (simulates restart)
    4. Verify data loaded correctly
 
 9. EDGE CASES TO TEST
    - Empty state
    - Non-existent items
    - Invalid input
    - Maximum values
    - Concurrent operations (if applicable)
 
 10. PERFORMANCE TESTING
     measure {
         // Code to measure
     }
     
     - Measures average execution time
     - Helps catch performance regressions
     - Run multiple times for accuracy
 
 11. RUNNING TESTS
     Xcode:
     - Command-U: Run all tests
     - Click diamond next to test: Run single test
     
     Command Line:
     xcodebuild -project Noty.xcodeproj \
                -scheme Noty \
                -destination 'platform=macOS' \
                test
 
 12. TEST COVERAGE
     Focus on:
     - Business logic (managers, utilities)
     - Data persistence
     - Edge cases
     - Error handling
     
     Skip:
     - Simple getters/setters
     - View code (test with UI tests instead)
     - Third-party code
 
 13. BEST PRACTICES
     - One assertion per concept
     - Clear failure messages
     - Isolated tests (no dependencies)
     - Fast execution
     - Deterministic results
     - Clean up resources
 
 14. COMMON PITFALLS
     ✗ Tests depend on execution order
     ✗ Shared state between tests
     ✗ Missing tearDown cleanup
     ✗ Testing implementation details
     ✗ Too many assertions in one test
     ✗ Slow tests (use mocks)
 */

