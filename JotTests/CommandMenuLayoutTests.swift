import XCTest
@testable import Jot

/// Tests for `CommandMenuLayout` — the source of truth for the slash-command
/// menu's dimensions. These exist because the menu's rendered height must
/// match the height used in `clampedCommandMenuPosition` for above/below
/// positioning. If they drift, the menu visually overlaps the "/" it was
/// anchored to when it flips above the cursor.
final class CommandMenuLayoutTests: XCTestCase {

    /// Composition contract: total height equals item grid + internal
    /// scroll-view spacer pair + outer card padding pair.
    func testTotalHeight_composesItemsScrollPaddingAndOuterPadding() {
        let itemCount = 3
        let expected = CommandMenuLayout.idealHeight(for: itemCount)
            + CommandMenuLayout.scrollContentPadding * 2
            + CommandMenuLayout.outerPadding * 2
        XCTAssertEqual(
            CommandMenuLayout.totalHeight(for: itemCount),
            expected,
            accuracy: 0.01
        )
    }

    /// Fixed baseline — 3 items × 36pt + 8pt scroll padding + 24pt outer
    /// padding = 140pt. Guards against drift between the positioning math
    /// and the actual rendered view.
    func testTotalHeight_knownBaselineThreeItems() {
        XCTAssertEqual(CommandMenuLayout.totalHeight(for: 3), 140, accuracy: 0.01)
    }

    /// The menu caps rendered items at `maxVisibleItems`, so adding items
    /// past that cap should not grow the total height — anything beyond
    /// scrolls internally.
    func testTotalHeight_capsAtMaxVisibleItems() {
        let atCap = CommandMenuLayout.totalHeight(for: CommandMenuLayout.maxVisibleItems)
        let wayOverCap = CommandMenuLayout.totalHeight(for: 42)
        XCTAssertEqual(atCap, wayOverCap, accuracy: 0.01)
    }

    /// Empty menu still has outer chrome even with no items. Helper must
    /// not return negative or nonsensical values for count 0.
    func testTotalHeight_zeroItems_returnsChromeOnly() {
        let expected = CommandMenuLayout.scrollContentPadding * 2
            + CommandMenuLayout.outerPadding * 2
        XCTAssertEqual(
            CommandMenuLayout.totalHeight(for: 0),
            expected,
            accuracy: 0.01
        )
    }

    // MARK: - menuTopY (slash anchor while filtering)

    /// When the menu is above the slash, shrinking `itemCount` moves the top
    /// downward by exactly the height delta so the bottom stays near the anchor.
    func testMenuTopY_above_shiftsTopByHeightDeltaWhenItemCountShrinks() {
        let anchor: CGFloat = 500
        let cursorH: CGFloat = 18
        let yFull = CommandMenuLayout.menuTopY(
            showsAbove: true,
            anchorCursorY: anchor,
            cursorHeight: cursorH,
            itemCount: 7
        )
        let yFew = CommandMenuLayout.menuTopY(
            showsAbove: true,
            anchorCursorY: anchor,
            cursorHeight: cursorH,
            itemCount: 2
        )
        let delta = yFew - yFull
        let heightDelta =
            CommandMenuLayout.totalHeight(for: 7) - CommandMenuLayout.totalHeight(for: 2)
        XCTAssertEqual(delta, heightDelta, accuracy: 0.01)
    }

    /// Below the slash, menu top does not depend on filtered item count.
    func testMenuTopY_below_independentOfItemCount() {
        let anchor: CGFloat = 100
        let cursorH: CGFloat = 16
        let y7 = CommandMenuLayout.menuTopY(
            showsAbove: false,
            anchorCursorY: anchor,
            cursorHeight: cursorH,
            itemCount: 7
        )
        let y2 = CommandMenuLayout.menuTopY(
            showsAbove: false,
            anchorCursorY: anchor,
            cursorHeight: cursorH,
            itemCount: 2
        )
        XCTAssertEqual(y7, y2, accuracy: 0.01)
        XCTAssertEqual(
            y7,
            anchor + cursorH + CommandMenuLayout.verticalAnchorGap,
            accuracy: 0.01
        )
    }
}
