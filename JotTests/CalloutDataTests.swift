import XCTest
@testable import Jot

final class CalloutDataTests: XCTestCase {

    func testSerializeWithoutPreferredWidthMatchesLegacyOpeningTag() {
        let data = CalloutData.empty(type: .info)
        let s = data.serialize()
        XCTAssertTrue(s.hasPrefix("[[callout|info]]"), s)
        XCTAssertTrue(s.hasSuffix("[[/callout]]"), s)
    }

    func testRoundTripPreferredContentWidth() {
        var data = CalloutData.empty(type: .warning)
        data.content = "hello"
        data.preferredContentWidth = 512.25
        let s = data.serialize()
        XCTAssertTrue(s.contains("[[callout|warning:512.25]]"), s)
        guard let back = CalloutData.deserialize(from: s) else {
            return XCTFail("deserialize failed")
        }
        XCTAssertEqual(back.type, .warning)
        XCTAssertEqual(back.content, "hello")
        XCTAssertNotNil(back.preferredContentWidth)
        XCTAssertEqual(Double(back.preferredContentWidth!), 512.25, accuracy: 0.001)
    }

    func testLegacyMarkupStillDeserializesWithNilPreferredWidth() {
        let legacy = "[[callout|tip]]line1\\nline2[[/callout]]"
        guard let data = CalloutData.deserialize(from: legacy) else {
            return XCTFail("deserialize failed")
        }
        XCTAssertEqual(data.type, .tip)
        XCTAssertEqual(data.content, "line1\nline2")
        XCTAssertNil(data.preferredContentWidth)
    }
}
