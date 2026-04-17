//
//  NoteParagraphStylerTests.swift
//  JotTests
//
//  Regression guards for the paragraph-style invariants in `NoteParagraphStyler`.
//  Previously only exercisable through the full Coordinator + NSTextView harness in
//  `TodoEditorInsertRegressionTests`; now testable against a bare `NSTextStorage`.
//

import AppKit
import XCTest

@testable import Jot

@MainActor
final class NoteParagraphStylerTests: XCTestCase {

    // MARK: - Heading level detection

    func testHeadingLevel_MapsPointSizeToHeadingLevel() {
        let h1Font = NSFont.systemFont(ofSize: TextFormattingManager.HeadingLevel.h1.fontSize)
        XCTAssertEqual(NoteParagraphStyler.headingLevel(for: h1Font), .h1)

        let h2Font = NSFont.systemFont(ofSize: TextFormattingManager.HeadingLevel.h2.fontSize)
        XCTAssertEqual(NoteParagraphStyler.headingLevel(for: h2Font), .h2)

        let h3Font = NSFont.systemFont(ofSize: TextFormattingManager.HeadingLevel.h3.fontSize)
        XCTAssertEqual(NoteParagraphStyler.headingLevel(for: h3Font), .h3)

        let bodyFont = NSFont.systemFont(ofSize: 13)
        XCTAssertNil(NoteParagraphStyler.headingLevel(for: bodyFont))
    }

    // MARK: - Blockquote paragraph style invariants

    /// Regression: blockquote paragraphs must carry `tailIndent = -4`,
    /// `lineBreakMode = .byWordWrapping`, and `headIndent = 20`. These match
    /// `TextFormattingManager.toggleBlockQuote`; divergence causes reload drift.
    func testStyleTodoParagraphs_BlockQuote_PreservesInvariants() {
        let storage = NSTextStorage(string: "quoted text\n")
        // Mark the paragraph as blockquote so styleTodoParagraphs enters the blockquote branch.
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.blockQuote, value: true, range: fullRange)

        NoteParagraphStyler.styleTodoParagraphs(in: storage, editedRange: nil)

        guard let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else {
            XCTFail("Expected .paragraphStyle on blockquote paragraph")
            return
        }
        XCTAssertEqual(style.tailIndent, -4,
            "Blockquote tailIndent must be -4")
        XCTAssertEqual(style.lineBreakMode, .byWordWrapping,
            "Blockquote lineBreakMode must be .byWordWrapping")
        XCTAssertEqual(style.headIndent, 20,
            "Blockquote headIndent must be 20")
    }

    // MARK: - Heading detection via first-character font peek

    /// Regression: heading detection reads `.font` at the paragraph's first character
    /// (single-point peek, not `enumerateAttribute`) — optimization landed in P1.
    /// A heading-font first character must trigger the heading branch.
    func testStyleTodoParagraphs_Heading_DetectsFromFirstCharacterFont() {
        let storage = NSTextStorage(string: "Title\n")
        let h1Font = NSFont.systemFont(ofSize: TextFormattingManager.HeadingLevel.h1.fontSize)
        storage.addAttribute(.font, value: h1Font, range: NSRange(location: 0, length: storage.length))

        NoteParagraphStyler.styleTodoParagraphs(in: storage, editedRange: nil)

        guard let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else {
            XCTFail("Expected .paragraphStyle on heading paragraph")
            return
        }
        XCTAssertEqual(style.paragraphSpacingBefore, 8, accuracy: 0.01,
            "Heading must have paragraphSpacingBefore = 8")
        XCTAssertEqual(style.paragraphSpacing, 12, accuracy: 0.01,
            "Heading must have paragraphSpacing = 12")
    }

    // MARK: - Arrow paragraph detection (legacy Unicode arrow at line start)

    /// Regression: a paragraph starting with `\u{2192} ` must trigger `isArrowParagraph`
    /// and apply the ordered-list paragraph style (hang-indent under the arrow).
    func testStyleTodoParagraphs_ArrowParagraph_AppliesOrderedListStyle() {
        let storage = NSTextStorage(string: "\u{2192} hello\n")

        NoteParagraphStyler.styleTodoParagraphs(in: storage, editedRange: nil)

        guard let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else {
            XCTFail("Expected .paragraphStyle on arrow paragraph")
            return
        }
        XCTAssertEqual(style.headIndent, 22,
            "Arrow paragraph should hang-indent like an ordered list (headIndent = 22)")
        XCTAssertEqual(style.firstLineHeadIndent, 0,
            "Arrow paragraph firstLineHeadIndent should be 0")
    }

    // MARK: - fixInconsistentFonts heading-font guard (Writing Tools protection)

    /// Regression: `fixInconsistentFonts` must NOT rewrite heading fonts to the body font.
    /// Writing Tools can inject Helvetica into a Charter document; the fix-up pass reverts
    /// body text to Charter, but heading runs must retain their heading size/family.
    func testFixInconsistentFonts_LeavesHeadingFontsAlone() {
        let storage = NSTextStorage(string: "Heading\n")
        let h1Size = TextFormattingManager.HeadingLevel.h1.fontSize
        let injectedHeadingFont = NSFont(name: "Helvetica", size: h1Size)
            ?? NSFont.systemFont(ofSize: h1Size)
        storage.addAttribute(.font, value: injectedHeadingFont, range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: storage.length))

        // Body-font expectation — heading must NOT be coerced to this size.
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let expected: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
        ]

        NoteParagraphStyler.fixInconsistentFonts(
            in: storage,
            scopeRange: nil,
            expectedAttributes: expected
        )

        guard let finalFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            XCTFail("Expected .font attribute on heading paragraph")
            return
        }
        XCTAssertEqual(finalFont.pointSize, h1Size, accuracy: 0.01,
            "Heading font size must not be downgraded to body size by fixInconsistentFonts")
    }

    // MARK: - fixInconsistentFonts skips attachment and inline-code runs

    /// Regression: attachment characters (U+FFFC) must not have their attributes rewritten;
    /// doing so strips custom keys like `.notelinkID` and causes attachments to vanish.
    func testFixInconsistentFonts_SkipsAttachmentCharacters() {
        let attachment = NSTextAttachment()
        let attrString = NSMutableAttributedString(attachment: attachment)
        // Decorate with a custom key that must survive the fix-up pass.
        let customKey = NSAttributedString.Key("TestCustomKey")
        attrString.addAttribute(customKey, value: "preserved", range: NSRange(location: 0, length: 1))

        let storage = NSTextStorage(attributedString: attrString)

        let bodyFont = NSFont.systemFont(ofSize: 13)
        let expected: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
        ]

        NoteParagraphStyler.fixInconsistentFonts(
            in: storage,
            scopeRange: nil,
            expectedAttributes: expected
        )

        let preserved = storage.attribute(customKey, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(preserved, "preserved",
            "Custom attribute keys on attachment ranges must survive fixInconsistentFonts")
    }
}
