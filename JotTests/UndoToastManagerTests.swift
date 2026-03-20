import XCTest
@testable import Jot

@MainActor
final class UndoToastManagerTests: XCTestCase {

    func testShowSetsCurrentToast() {
        let manager = UndoToastManager()
        manager.show("Test message") { }

        XCTAssertNotNil(manager.currentToast)
        XCTAssertEqual(manager.currentToast?.message, "Test message")
    }

    func testPerformUndoExecutesClosureAndDismisses() {
        let manager = UndoToastManager()
        var undoCalled = false
        manager.show("Test") { undoCalled = true }

        manager.performUndo()

        XCTAssertTrue(undoCalled)
        XCTAssertNil(manager.currentToast)
    }

    func testDismissClearsToast() {
        let manager = UndoToastManager()
        manager.show("Test") { }

        manager.dismiss()

        XCTAssertNil(manager.currentToast)
    }

    func testNewToastReplacesOld() {
        let manager = UndoToastManager()
        manager.show("First") { }
        let firstID = manager.currentToast?.id

        manager.show("Second") { }

        XCTAssertEqual(manager.currentToast?.message, "Second")
        XCTAssertNotEqual(manager.currentToast?.id, firstID)
    }

    func testPerformUndoWithNoToastIsNoOp() {
        let manager = UndoToastManager()
        // Should not crash
        manager.performUndo()
        XCTAssertNil(manager.currentToast)
    }

    func testReplacedToastUndoDoesNotFireOldClosure() {
        let manager = UndoToastManager()
        var firstUndoCalled = false
        var secondUndoCalled = false

        manager.show("First") { firstUndoCalled = true }
        manager.show("Second") { secondUndoCalled = true }

        manager.performUndo()

        XCTAssertFalse(firstUndoCalled)
        XCTAssertTrue(secondUndoCalled)
    }

    func testAutoDismissAfterTimeout() async throws {
        let manager = UndoToastManager()
        manager.show("Auto dismiss") { }

        XCTAssertNotNil(manager.currentToast)

        // Wait slightly longer than the 5-second timer
        try await Task.sleep(for: .seconds(5.5))

        XCTAssertNil(manager.currentToast)
    }
}
