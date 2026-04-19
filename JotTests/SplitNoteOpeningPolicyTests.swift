import XCTest
@testable import Jot

final class SplitNoteOpeningPolicyTests: XCTestCase {
    func testResolveReplacesPrimaryPaneWhenSplitIsVisibleAndPrimaryIsFocused() {
        let primaryID = UUID()
        let secondaryID = UUID()
        let targetID = UUID()

        let result = SplitNoteOpeningPolicy.resolve(
            targetNoteID: targetID,
            context: SplitNoteOpeningContext(
                isSplitVisible: true,
                primaryNoteID: primaryID,
                secondaryNoteID: secondaryID,
                focusedPane: .primary
            )
        )

        XCTAssertEqual(result.action, .replacePrimary)
        XCTAssertEqual(result.primaryNoteID, targetID)
        XCTAssertEqual(result.secondaryNoteID, secondaryID)
        XCTAssertEqual(result.selectedNoteID, targetID)
        XCTAssertEqual(result.focusedPane, .primary)
        XCTAssertTrue(result.keepsSplitVisible)
    }

    func testResolveReplacesSecondaryPaneWhenSplitIsVisibleAndSecondaryIsFocused() {
        let primaryID = UUID()
        let secondaryID = UUID()
        let targetID = UUID()

        let result = SplitNoteOpeningPolicy.resolve(
            targetNoteID: targetID,
            context: SplitNoteOpeningContext(
                isSplitVisible: true,
                primaryNoteID: primaryID,
                secondaryNoteID: secondaryID,
                focusedPane: .secondary
            )
        )

        XCTAssertEqual(result.action, .replaceSecondary)
        XCTAssertEqual(result.primaryNoteID, primaryID)
        XCTAssertEqual(result.secondaryNoteID, targetID)
        XCTAssertEqual(result.selectedNoteID, targetID)
        XCTAssertEqual(result.focusedPane, .secondary)
        XCTAssertTrue(result.keepsSplitVisible)
    }

    func testResolveFocusesExistingOppositePaneInsteadOfDuplicatingNote() {
        let primaryID = UUID()
        let secondaryID = UUID()

        let result = SplitNoteOpeningPolicy.resolve(
            targetNoteID: primaryID,
            context: SplitNoteOpeningContext(
                isSplitVisible: true,
                primaryNoteID: primaryID,
                secondaryNoteID: secondaryID,
                focusedPane: .secondary
            )
        )

        XCTAssertEqual(result.action, .focusExistingPrimary)
        XCTAssertEqual(result.primaryNoteID, primaryID)
        XCTAssertEqual(result.secondaryNoteID, secondaryID)
        XCTAssertEqual(result.selectedNoteID, primaryID)
        XCTAssertEqual(result.focusedPane, .primary)
        XCTAssertTrue(result.keepsSplitVisible)
    }

    func testResolveFallsBackToSingleNoteWhenSplitIsNotVisible() {
        let targetID = UUID()

        let result = SplitNoteOpeningPolicy.resolve(
            targetNoteID: targetID,
            context: SplitNoteOpeningContext(
                isSplitVisible: false,
                primaryNoteID: UUID(),
                secondaryNoteID: UUID(),
                focusedPane: .secondary
            )
        )

        XCTAssertEqual(result.action, .openSingle)
        XCTAssertEqual(result.selectedNoteID, targetID)
        XCTAssertFalse(result.keepsSplitVisible)
    }
}
