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

    // MARK: - Inline code

    /// `[[ic]]...[[/ic]]` must survive deserialize → serialize for card-style markup paths.
    func testInlineCodeTagRoundTrip() {
        let input = "[[ic]]read_file[[/ic]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        let roundTrip = RichTextSerializer.serializeAttributedString(attributed)
        XCTAssertEqual(roundTrip, input)
        XCTAssertEqual(attributed.attribute(.inlineCode, at: 0, effectiveRange: nil) as? Bool, true)
    }

    // MARK: - Malformed color tag recovery (C2)

    /// Regression: `[[color|HEX]]` with malformed hex (neither 6 nor 8 chars) used to fall
    /// through the two length-specific branches and leak the raw tag as individual literal
    /// characters (`[`, `[`, `c`, `o`, `l`, `o`, `r`, `|`, …). Must degrade gracefully.
    func testMalformedColorTag_DoesNotLeakLiteralBrackets() {
        let input = "[[color|GGGGG]]hello[[/color]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        let plain = attributed.string
        XCTAssertFalse(plain.contains("[["),
            "Malformed color tag must degrade gracefully, not emit literal bracket characters; got: \(plain.debugDescription)")
        XCTAssertFalse(plain.contains("color|"),
            "Malformed color tag must not leak the 'color|' token as visible text; got: \(plain.debugDescription)")
    }

    // MARK: - Basic inline tag round-trips (test coverage gap)

    func testBoldRoundTrip() {
        let input = "[[b]]hello[[/b]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute on bold run")
            return
        }
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testItalicRoundTrip() {
        let input = "[[i]]hello[[/i]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute on italic run")
            return
        }
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
    }

    func testUnderlineRoundTrip() {
        let input = "[[u]]hello[[/u]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        let style = attributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testStrikethroughRoundTrip() {
        let input = "[[s]]hello[[/s]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        let style = attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testColorHexRoundTrip() {
        let input = "[[color|ff0000]]hello[[/color]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        let roundTrip = RichTextSerializer.serializeAttributedString(attributed)
        XCTAssertEqual(roundTrip.lowercased(), input.lowercased(),
            "Color hex round-trip should be stable; got: \(roundTrip)")
        let isCustomColor = attributed.attribute(
            TextFormattingManager.customTextColorKey, at: 0, effectiveRange: nil) as? Bool
        XCTAssertEqual(isCustomColor, true, "Custom color flag must be set on colored run")
    }

    /// Canonical nesting order (bold > italic > ic > underline > strikethrough) means
    /// `[[b]][[u]]x[[/u]][[/b]]` should round-trip exactly.
    func testNestedBoldUnderlineRoundTrip() {
        let input = "[[b]][[u]]hello[[/u]][[/b]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute")
            return
        }
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
            "Nested bold+underline: bold trait must survive")
        let underline = attributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue,
            "Nested bold+underline: underline must survive")
    }

    /// `[[ic]]` + `[[b]]` co-occurrence must produce a bold monospace run.
    func testInlineCodeBoldCoOccurrence() {
        let input = "[[b]][[ic]]code[[/ic]][[/b]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        XCTAssertEqual(RichTextSerializer.serializeAttributedString(attributed), input)
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute")
            return
        }
        XCTAssertTrue(font.isFixedPitch, "Monospace font required for inline-code")
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
            "Bold trait must apply on top of inline-code font")
        XCTAssertEqual(attributed.attribute(.inlineCode, at: 0, effectiveRange: nil) as? Bool, true)
    }

    /// Unclosed opening tag must not crash; the text should still render with the open tag's
    /// formatting applied up to end-of-string (via `flushBuffer` at the bottom of the loop).
    func testUnclosedBoldTagDoesNotCrash() {
        let attributed = RichTextSerializer.deserializeToAttributedString("[[b]]no close")
        XCTAssertEqual(attributed.string, "no close",
            "Unclosed tag must still emit its inner text without leaking the tag")
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute on buffered run")
            return
        }
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
            "Unclosed `[[b]]` must still apply bold to its inner text")
    }

    /// P3 regression guard: the shared helper is the single source of truth for inline-code
    /// font size, weight, and trait handling. A manual monospace font construction elsewhere
    /// would bypass this.
    func testInlineCodeFontHelperProducesMonospace() {
        let font = RichTextSerializer.inlineCodeFont(bold: false, italic: false)
        XCTAssertTrue(font.isFixedPitch, "Inline-code helper must return a monospace font")
        let boldFont = RichTextSerializer.inlineCodeFont(bold: true, italic: false)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        let italicFont = RichTextSerializer.inlineCodeFont(bold: false, italic: true)
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
    }

    // MARK: - Color + inline-code composition (H3)

    /// A run wrapped in `[[color|...]]` that is also `[[ic]]...[[/ic]]` must carry BOTH
    /// the custom foreground color AND the monospace font + `.inlineCode` attribute.
    /// The color branch read other format state (bold, italic, …) but not inline-code,
    /// dropping the monospace font for colored code runs.
    func testColorAroundInlineCode_PreservesBothAttributes() {
        let input = "[[color|ff0000]][[ic]]code[[/ic]][[/color]]"
        let attributed = RichTextSerializer.deserializeToAttributedString(input)
        guard attributed.length > 0 else {
            XCTFail("Expected non-empty deserialize output")
            return
        }
        let isInlineCode = attributed.attribute(.inlineCode, at: 0, effectiveRange: nil) as? Bool
        XCTAssertEqual(isInlineCode, true,
            "Inline-code attribute must survive being wrapped in [[color|...]]")
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute on inline-code run inside color")
            return
        }
        XCTAssertTrue(font.isFixedPitch,
            "Inline-code font inside [[color|...]] must remain monospaced; got \(font.fontName)")
    }
}
