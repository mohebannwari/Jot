import XCTest
@testable import Jot

final class SplitPresentationPolicyTests: XCTestCase {
    func testPlainGlobalSearchClosesVisibleSplitAndKeepsTargetNote() {
        let targetID = UUID()

        let result = SplitPresentationPolicy.resolvePlainGlobalSearchSelection(
            targetNoteID: targetID,
            isSplitVisible: true
        )

        XCTAssertEqual(result.selectedNoteID, targetID)
        XCTAssertTrue(result.closesSplit)
    }

    func testPlainGlobalSearchDoesNotCloseSplitWhenSplitIsHidden() {
        let targetID = UUID()

        let result = SplitPresentationPolicy.resolvePlainGlobalSearchSelection(
            targetNoteID: targetID,
            isSplitVisible: false
        )

        XCTAssertEqual(result.selectedNoteID, targetID)
        XCTAssertFalse(result.closesSplit)
    }

    func testSplitSessionActivationDefaultsToPrimaryPane() {
        let primaryID = UUID()
        let secondaryID = UUID()

        let result = SplitPresentationPolicy.resolveSplitSessionActivation(
            primaryNoteID: primaryID,
            secondaryNoteID: secondaryID,
            targetNoteID: nil
        )

        XCTAssertEqual(result.selectedNoteID, primaryID)
        XCTAssertEqual(result.focusedPane, .primary)
    }

    func testSplitSessionActivationTargetsSecondaryPaneWhenOpeningSecondaryNote() {
        let primaryID = UUID()
        let secondaryID = UUID()

        let result = SplitPresentationPolicy.resolveSplitSessionActivation(
            primaryNoteID: primaryID,
            secondaryNoteID: secondaryID,
            targetNoteID: secondaryID
        )

        XCTAssertEqual(result.selectedNoteID, secondaryID)
        XCTAssertEqual(result.focusedPane, .secondary)
    }
}
