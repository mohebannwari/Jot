//
//  CodeBlockDataTests.swift
//  JotTests
//

import XCTest

@testable import Jot

final class CodeBlockDataTests: XCTestCase {

    func testSerializeDeserializeRoundTripWithPreferredWidth() {
        var data = CodeBlockData(language: "swift", code: "let x = 1")
        data.preferredContentWidth = 512.5

        let s = data.serialize()
        XCTAssertTrue(s.contains("swift:512.50]]") || s.contains("swift:512.5]]"), "Width suffix in open tag: \(s)")

        guard let back = CodeBlockData.deserialize(from: s) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertEqual(back.language, "swift")
        XCTAssertEqual(back.code, "let x = 1")
        XCTAssertNotNil(back.preferredContentWidth)
        XCTAssertEqual(Double(back.preferredContentWidth!), 512.5, accuracy: 0.01)
    }

    func testDeserializeLegacyNoWidth() {
        let legacy = "[[codeblock|plaintext]]hello[[/codeblock]]"
        guard let data = CodeBlockData.deserialize(from: legacy) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertNil(data.preferredContentWidth)
        XCTAssertEqual(data.language, "plaintext")
        XCTAssertEqual(data.code, "hello")
    }

    func testHeaderWithColonInLanguageDoesNotStripWhenSuffixNotNumeric() {
        // Hypothetical custom id `foo:bar` — suffix is not a positive double, whole header stays language.
        let s = "[[codeblock|foo:bar]]x[[/codeblock]]"
        guard let data = CodeBlockData.deserialize(from: s) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertEqual(data.language, "foo:bar")
        XCTAssertNil(data.preferredContentWidth)
    }
}
