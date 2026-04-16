import AppKit
import XCTest
@testable import Jot

/// Regression tests that guard against serialize → deserialize drift for paragraph-level styles.
///
/// `TextFormattingManager.toggleBlockQuote` and `TextFormattingManager.toggleNumberedList`
/// apply paragraph styles with specific metrics (blockquote `tailIndent = -4` +
/// `lineBreakMode = .byWordWrapping`, ordered list `headIndent = 22`). The deserializer
/// must produce identical metrics so a saved note reloads with the same geometry it had
/// while being edited.
final class RichTextSerializerTests: XCTestCase {

    // MARK: - Blockquote

    /// `[[quote]]...[[/quote]]` deserialize must preserve `tailIndent` and `lineBreakMode`
    /// so wrap geometry after reload matches the live-toggled state.
    func testBlockQuoteDeserialize_PreservesTailIndentAndLineBreakMode() {
        let attributed = RichTextSerializer.deserializeToAttributedString("[[quote]]hello[[/quote]]")

        guard attributed.length > 0 else {
            XCTFail("Deserialized blockquote produced empty attributed string")
            return
        }
        guard let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else {
            XCTFail("Expected .paragraphStyle attribute on deserialized blockquote content")
            return
        }

        XCTAssertEqual(style.tailIndent, -4,
            "Blockquote tailIndent must be -4 to match TextFormattingManager.toggleBlockQuote")
        XCTAssertEqual(style.lineBreakMode, .byWordWrapping,
            "Blockquote lineBreakMode must be .byWordWrapping to match live toggle")
        XCTAssertEqual(style.firstLineHeadIndent, 20,
            "Existing firstLineHeadIndent must still be 20 (regression guard)")
        XCTAssertEqual(style.headIndent, 20,
            "Existing headIndent must still be 20 (regression guard)")
    }

    /// `blockQuoteParagraphStyle()` factory must itself produce the canonical style,
    /// not just the deserialize path. Card/tab overlays also call this helper.
    func testBlockQuoteParagraphStyleFactory_HasCorrectMetrics() {
        let style = RichTextSerializer.blockQuoteParagraphStyle()

        XCTAssertEqual(style.tailIndent, -4)
        XCTAssertEqual(style.lineBreakMode, .byWordWrapping)
        XCTAssertEqual(style.firstLineHeadIndent, 20)
        XCTAssertEqual(style.headIndent, 20)
    }

    // MARK: - Ordered list

    /// `[[ol|N]]` deserialize must attach `orderedListParagraphStyle()` so wrapped
    /// numbered-list items hang-indent under the number prefix.
    func testOrderedListDeserialize_AppliesOrderedListParagraphStyle() {
        // Prefix is "<n>. " so we check the paragraph style on that prefix character.
        let attributed = RichTextSerializer.deserializeToAttributedString("[[ol|3]]")

        guard attributed.length > 0 else {
            XCTFail("Deserialized [[ol|3]] produced empty attributed string")
            return
        }
        let number = attributed.attribute(
            .orderedListNumber, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(number, 3, "orderedListNumber attribute must carry the parsed integer")

        guard let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else {
            XCTFail("Expected .paragraphStyle attribute on deserialized [[ol|N]] content")
            return
        }
        XCTAssertEqual(style.headIndent, 22,
            "Ordered list headIndent must be 22 so wrapped lines hang-indent under the number")
        XCTAssertEqual(style.firstLineHeadIndent, 0,
            "Ordered list firstLineHeadIndent must be 0 so the number prefix sits at the margin")
    }
}
