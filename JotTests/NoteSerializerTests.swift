//
//  NoteSerializerTests.swift
//  JotTests
//
//  Regression guards for the editor's attachment-aware `NoteSerializer.serialize(_:)`.
//  Previously exercisable only through the full Coordinator + NSTextView harness; now
//  testable against a bare `NSTextStorage`.
//

import AppKit
import CoreLocation
import MapKit
import XCTest

@testable import Jot

@MainActor
final class NoteSerializerTests: XCTestCase {

    // MARK: - Plain text

    func testPlainText_NoTagsEmitted() {
        let storage = NSTextStorage(string: "hello world")
        XCTAssertEqual(NoteSerializer.serialize(storage), "hello world")
    }

    // MARK: - Inline formatting

    func testBoldFont_EmitsBoldTags() {
        let storage = NSTextStorage(string: "bold text")
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let boldFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        storage.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: storage.length))

        let output = NoteSerializer.serialize(storage)
        XCTAssertTrue(output.contains("[[b]]"), "Bold font must emit [[b]] tag; got: \(output)")
        XCTAssertTrue(output.contains("[[/b]]"), "Bold font must emit matching [[/b]] close; got: \(output)")
        XCTAssertTrue(output.contains("bold text"), "Run text must survive; got: \(output)")
    }

    func testUnderline_EmitsUnderlineTags() {
        let storage = NSTextStorage(string: "underlined")
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                             range: NSRange(location: 0, length: storage.length))
        let output = NoteSerializer.serialize(storage)
        XCTAssertTrue(output.contains("[[u]]underlined[[/u]]"),
            "Underline run must emit wrapping tags; got: \(output)")
    }

    func testStrikethrough_EmitsStrikethroughTags() {
        let storage = NSTextStorage(string: "struck")
        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                             range: NSRange(location: 0, length: storage.length))
        let output = NoteSerializer.serialize(storage)
        XCTAssertTrue(output.contains("[[s]]struck[[/s]]"),
            "Strikethrough run must emit wrapping tags; got: \(output)")
    }

    // MARK: - Blockquote

    func testBlockQuote_EmitsQuoteTags() {
        let storage = NSTextStorage(string: "quoted")
        storage.addAttribute(.blockQuote, value: true,
                             range: NSRange(location: 0, length: storage.length))
        let output = NoteSerializer.serialize(storage)
        XCTAssertTrue(output.contains("[[quote]]quoted[[/quote]]"),
            ".blockQuote attribute must emit [[quote]] wrapping tags; got: \(output)")
    }

    // MARK: - Ordered list prefix

    /// Regression: when a run has `.orderedListNumber`, the serializer emits `[[ol|N]]`
    /// and drops the run text (which is the "N. " prefix — reconstructed on deserialize).
    func testOrderedListNumber_EmitsOlTag_DropsPrefixText() {
        let storage = NSTextStorage(string: "3. rest of line")
        // Mark only the "3. " prefix (3 chars) with orderedListNumber.
        storage.addAttribute(.orderedListNumber, value: 3,
                             range: NSRange(location: 0, length: 3))
        let output = NoteSerializer.serialize(storage)
        XCTAssertTrue(output.contains("[[ol|3]]"), "Must emit [[ol|3]]; got: \(output)")
        // Prefix "3. " must NOT appear in output (encoded in the tag).
        XCTAssertFalse(output.contains("3. "),
            "Ordered-list prefix text must be dropped (encoded in [[ol|N]]); got: \(output)")
        XCTAssertTrue(output.contains("rest of line"),
            "Rest-of-line text must survive; got: \(output)")
    }

    // MARK: - Attachments

    func testDividerAttachment_EmitsDividerTag() {
        let attachment = NoteDividerAttachment()
        let attributed = NSMutableAttributedString(attachment: attachment)
        let storage = NSTextStorage(attributedString: attributed)
        XCTAssertEqual(NoteSerializer.serialize(storage), "[[divider]]")
    }

    func testArrowAttachment_EmitsArrowTag() {
        let attachment = NoteArrowAttachment(data: nil, ofType: nil)
        let attributed = NSMutableAttributedString(attachment: attachment)
        let storage = NSTextStorage(attributedString: attributed)
        XCTAssertEqual(NoteSerializer.serialize(storage), "[[arrow]]")
    }

    func testMapAttachment_EmitsExactMapToken() {
        let mapData = MapBlockData(
            title: "Park",
            subtitle: "North Gate",
            pinCoordinate: CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954),
            viewportCenter: CLLocationCoordinate2D(latitude: 52.520108, longitude: 13.405054),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.010000, longitudeDelta: 0.020000),
            widthRatio: 0.3333
        )
        let attachment = NoteMapAttachment(mapData: mapData)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttribute(.mapSerializedData, value: mapData.serialize(), range: NSRange(location: 0, length: attributed.length))
        let storage = NSTextStorage(attributedString: attributed)

        XCTAssertEqual(
            NoteSerializer.serialize(storage),
            "[[map|Park|North Gate|52.520008|13.404954|52.520108|13.405054|0.010000|0.020000|0.3333]]"
        )
    }

    func testMalformedMapTokenFailsSafely() {
        XCTAssertNil(MapBlockData.deserialize(from: "[[map|only|three]]"))
        XCTAssertNil(MapBlockData.deserialize(from: "[[map|title|subtitle|bad|coord|0|0|0|0|0.33]]"))
    }

    // MARK: - Corrupted-block passthrough

    /// Regression: `.corruptedBlock` attribute must short-circuit serialization and emit
    /// the stored raw markup verbatim, enabling lossless round-trip when deserialize fails.
    func testCorruptedBlock_EmitsRawMarkupVerbatim() {
        let storage = NSTextStorage(string: "\u{FFFC}")
        let rawMarkup = "[[callout|warning|original raw content]]"
        storage.addAttribute(.corruptedBlock, value: rawMarkup,
                             range: NSRange(location: 0, length: storage.length))
        XCTAssertEqual(NoteSerializer.serialize(storage), rawMarkup)
    }

    // MARK: - Mixed inline + plain

    func testMixedInline_BoldInsidePlain_WrapsOnlyBoldRun() {
        let storage = NSTextStorage(string: "pre bold post")
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let boldFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        // Bold on "bold" (4 chars at offset 4)
        storage.addAttribute(.font, value: boldFont, range: NSRange(location: 4, length: 4))

        let output = NoteSerializer.serialize(storage)
        // Expect: "pre [[b]]bold[[/b]] post" (exact nesting may vary with attribute runs;
        // just confirm the bold tags wrap only the bold word).
        XCTAssertTrue(output.contains("[[b]]bold[[/b]]"),
            "Bold run must wrap only the bold glyphs; got: \(output)")
        XCTAssertTrue(output.hasPrefix("pre "),
            "Leading plain run must serialize without tags; got: \(output)")
        XCTAssertTrue(output.hasSuffix(" post"),
            "Trailing plain run must serialize without tags; got: \(output)")
    }

    // MARK: - Empty storage

    func testEmptyStorage_ReturnsEmptyString() {
        let storage = NSTextStorage(string: "")
        XCTAssertEqual(NoteSerializer.serialize(storage), "")
    }
}
