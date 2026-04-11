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
}
