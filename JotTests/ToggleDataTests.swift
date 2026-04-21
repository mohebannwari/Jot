//
//  ToggleDataTests.swift
//  JotTests
//

import XCTest

@testable import Jot

final class ToggleDataTests: XCTestCase {

    // MARK: - Empty constructor

    func testEmptyReturnsExpandedBlankToggle() {
        let data = ToggleData.empty()
        XCTAssertEqual(data.title, "")
        XCTAssertEqual(data.content, "")
        XCTAssertTrue(data.isExpanded)
        XCTAssertNil(data.preferredContentWidth)
    }

    // MARK: - Round-trip

    func testRoundTripPlainTitleAndContent() {
        let original = ToggleData(
            title: "My toggle",
            content: "Line one\nLine two",
            isExpanded: true,
            preferredContentWidth: nil
        )
        let s = original.serialize()
        XCTAssertTrue(s.hasPrefix("[[toggle|"))
        XCTAssertTrue(s.hasSuffix("[[/toggle]]"))

        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertEqual(back.title, original.title)
        XCTAssertEqual(back.content, original.content)
        XCTAssertEqual(back.isExpanded, original.isExpanded)
        XCTAssertNil(back.preferredContentWidth)
    }

    func testRoundTripCollapsedState() {
        let data = ToggleData(
            title: "Collapsed",
            content: "Hidden body",
            isExpanded: false,
            preferredContentWidth: nil
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertFalse(back.isExpanded)
    }

    func testRoundTripPreservesPreferredWidth() {
        let data = ToggleData(
            title: "Width",
            content: "body",
            isExpanded: true,
            preferredContentWidth: 420.25
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertNotNil(back.preferredContentWidth)
        XCTAssertEqual(Double(back.preferredContentWidth!), 420.25, accuracy: 0.01)
    }

    // MARK: - Escape safety

    func testTitleWithBracketsAndTabsAndNewlinesRoundTrips() {
        let nasty = "Title [[with]] \t tabs\nand\nnewlines"
        let data = ToggleData(
            title: nasty,
            content: "",
            isExpanded: true,
            preferredContentWidth: nil
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertEqual(back.title, nasty)
    }

    func testContentContainingTogglerMarkerLiteralRoundTrips() {
        // Content that literally contains "[[toggle|" and "[[/toggle]]" must
        // survive round-trip — the escape table prevents the deserializer from
        // mistaking inner brackets for the outer block terminator.
        let innerLiteral = "[[toggle|1|]]inner title\t\tinner body[[/toggle]]"
        let data = ToggleData(
            title: "Outer",
            content: innerLiteral,
            isExpanded: true,
            preferredContentWidth: nil
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertEqual(back.title, "Outer")
        XCTAssertEqual(back.content, innerLiteral)
    }

    func testContentWithDoubleTabSeparatorRoundTrips() {
        // Literal double-tab in content must not be confused with the
        // title/content separator.
        let content = "foo\t\tbar"
        let data = ToggleData(
            title: "t",
            content: content,
            isExpanded: true,
            preferredContentWidth: nil
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertEqual(back.content, content)
    }

    func testContentWithRichTextMarkersRoundTrips() {
        // Rich-text body content contains legitimate markers like [[b]], [[h1]],
        // [[image|...]] — these must survive intact (their brackets are escaped,
        // then unescaped back on read).
        let rich = "[[b]]bold[[/b]] regular [[h1]]heading[[/h1]] [[image|||abc.png]]"
        let data = ToggleData(
            title: "Rich",
            content: rich,
            isExpanded: true,
            preferredContentWidth: nil
        )
        let s = data.serialize()
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize failed: \(s)")
            return
        }
        XCTAssertEqual(back.content, rich)
    }

    // MARK: - Malformed input

    func testDeserializeRejectsMissingPrefix() {
        XCTAssertNil(ToggleData.deserialize(from: "not a toggle"))
        XCTAssertNil(ToggleData.deserialize(from: "[[tabs|0|222|x]][[/tabs]]"))
    }

    func testDeserializeRejectsMissingCloseBracket() {
        XCTAssertNil(ToggleData.deserialize(from: "[[toggle|1| title\t\tbody[[/toggle]]"))
    }

    func testDeserializeRejectsMissingClosingTag() {
        XCTAssertNil(ToggleData.deserialize(from: "[[toggle|1|]]title\t\tbody"))
    }

    func testDeserializeHandlesEmptyContent() {
        let s = "[[toggle|1|]]\t\t[[/toggle]]"
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("deserialize of empty toggle should succeed")
            return
        }
        XCTAssertEqual(back.title, "")
        XCTAssertEqual(back.content, "")
        XCTAssertTrue(back.isExpanded)
    }

    func testDeserializeTreatsInvalidWidthAsNil() {
        let s = "[[toggle|1|not_a_number]]Title\t\tBody[[/toggle]]"
        guard let back = ToggleData.deserialize(from: s) else {
            XCTFail("malformed width should degrade to nil, not reject the block")
            return
        }
        XCTAssertNil(back.preferredContentWidth)
    }
}
