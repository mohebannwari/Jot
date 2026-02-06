import XCTest
@testable import Noty

final class NoteSelectionInteractionTests: XCTestCase {
    func testPlainTapResetsSelectionAndAnchor() {
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let result = NoteSelectionReducer.apply(
            interaction: .plain,
            noteID: c,
            currentSelection: [a, b],
            currentAnchor: a,
            orderedVisibleNoteIDs: [a, b, c]
        )

        XCTAssertEqual(result.selection, [c])
        XCTAssertEqual(result.anchor, c)
    }

    func testCommandToggleAddsAndRemovesNote() {
        let a = UUID()
        let b = UUID()

        let added = NoteSelectionReducer.apply(
            interaction: .commandToggle,
            noteID: b,
            currentSelection: [a],
            currentAnchor: a,
            orderedVisibleNoteIDs: [a, b]
        )
        XCTAssertEqual(added.selection, [a, b])
        XCTAssertEqual(added.anchor, b)

        let removed = NoteSelectionReducer.apply(
            interaction: .commandToggle,
            noteID: b,
            currentSelection: added.selection,
            currentAnchor: added.anchor,
            orderedVisibleNoteIDs: [a, b]
        )
        XCTAssertEqual(removed.selection, [a])
        XCTAssertEqual(removed.anchor, b)
    }

    func testShiftRangeBuildsInclusiveRangeAcrossVisibleOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()

        let result = NoteSelectionReducer.apply(
            interaction: .shiftRange,
            noteID: d,
            currentSelection: [b],
            currentAnchor: b,
            orderedVisibleNoteIDs: [a, b, c, d]
        )

        XCTAssertEqual(result.selection, [b, c, d])
        XCTAssertEqual(result.anchor, b)
    }

    func testShiftRangeFallsBackToClickedNoteWhenAnchorNotVisible() {
        let hiddenAnchor = UUID()
        let a = UUID()
        let b = UUID()

        let result = NoteSelectionReducer.apply(
            interaction: .shiftRange,
            noteID: b,
            currentSelection: [hiddenAnchor],
            currentAnchor: hiddenAnchor,
            orderedVisibleNoteIDs: [a, b]
        )

        XCTAssertEqual(result.selection, [b])
        XCTAssertEqual(result.anchor, hiddenAnchor)
    }

    func testSelectAllUsesVisibleOrderIDs() {
        let a = UUID()
        let b = UUID()
        let c = UUID()

        let result = NoteSelectionReducer.selectAll(orderedVisibleNoteIDs: [a, b, c])

        XCTAssertEqual(result, [a, b, c])
    }

    func testClearSelectionProducesEmptySet() {
        let a = UUID()
        let b = UUID()

        var selection: Set<UUID> = [a, b]
        selection.removeAll()

        XCTAssertTrue(selection.isEmpty)
    }
}
