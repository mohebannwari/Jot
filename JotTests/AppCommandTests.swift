import XCTest
@testable import Jot

final class AppCommandTests: XCTestCase {
    func testSimpleCommandPostsExistingNotificationName() {
        let center = NotificationCenter()
        let expectation = expectation(description: "legacy create-note notification received")
        let observer = center.addObserver(forName: .createNewNote, object: nil, queue: nil) { notification in
            XCTAssertEqual(notification.appCommand, .createNewNote)
            expectation.fulfill()
        }
        defer { center.removeObserver(observer) }

        center.post(.createNewNote)

        wait(for: [expectation], timeout: 0.1)
    }

    func testSelectionCommandPreservesLegacyActionPayload() {
        let command = AppCommand.noteSelection(.exportSelection)
        let notification = Notification(
            name: command.name,
            object: command.object,
            userInfo: command.userInfo
        )

        XCTAssertEqual(command.name, .noteSelectionCommandTriggered)
        XCTAssertEqual(notification.userInfo?["action"] as? String, "exportSelection")
        XCTAssertEqual(notification.appCommand, command)
    }

    func testNavigateCommandPreservesLegacyDirectionPayload() {
        let command = AppCommand.navigateNote(.up)
        let notification = Notification(
            name: command.name,
            object: command.object,
            userInfo: command.userInfo
        )

        XCTAssertEqual(command.name, .navigateNote)
        XCTAssertEqual(notification.userInfo?["direction"] as? String, "up")
        XCTAssertEqual(notification.appCommand, command)
    }

    func testNoteIDCommandPreservesLegacyUserInfoPayload() {
        let noteID = UUID()
        let command = AppCommand.openNoteFromSpotlight(noteID: noteID)
        let notification = Notification(
            name: command.name,
            object: command.object,
            userInfo: command.userInfo
        )

        XCTAssertEqual(command.name, .openNoteFromSpotlight)
        XCTAssertEqual(notification.userInfo?["noteID"] as? UUID, noteID)
        XCTAssertEqual(notification.appCommand, command)
    }

    func testPropertiesPanelTodoCommandPreservesLegacyObjectAndLineIndex() {
        let editorInstanceID = UUID()
        let command = AppCommand.propertiesPanelToggleTodo(
            editorInstanceID: editorInstanceID,
            lineIndex: 3
        )
        let notification = Notification(
            name: command.name,
            object: command.object,
            userInfo: command.userInfo
        )

        XCTAssertEqual(command.name, .propertiesPanelToggleTodo)
        XCTAssertEqual(notification.object as? UUID, editorInstanceID)
        XCTAssertEqual(notification.userInfo?["lineIndex"] as? Int, 3)
        XCTAssertEqual(notification.appCommand, command)
    }
}
