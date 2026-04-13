//
//  TabsContainerDataTests.swift
//  JotTests
//

import XCTest

@testable import Jot

final class TabsContainerDataTests: XCTestCase {

    func testSerializeDeserializeRoundTripWithPreferredWidth() {
        var data = TabsContainerData.empty()
        data.preferredContentWidth = 512.5
        data.panes[0].name = "A"
        data.panes[0].content = "hello"

        let s = data.serialize()
        XCTAssertTrue(s.contains("|512.50]]") || s.contains("|512.5]]"), "Width should appear in header: \(s)")

        guard let back = TabsContainerData.deserialize(from: s) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertNotNil(back.preferredContentWidth)
        XCTAssertEqual(Double(back.preferredContentWidth!), 512.5, accuracy: 0.01)
        XCTAssertEqual(back.panes.count, 1)
        XCTAssertEqual(back.panes[0].name, "A")
        XCTAssertEqual(back.panes[0].content, "hello")
    }

    func testDeserializeLegacyFourPartHeaderWithoutWidth() {
        let legacy = "[[tabs|0|222|Tab 1|]]\t\t[[/tabs]]"
        guard let data = TabsContainerData.deserialize(from: legacy) else {
            XCTFail("deserialize failed")
            return
        }
        XCTAssertNil(data.preferredContentWidth)
        XCTAssertEqual(data.panes.count, 1)
        XCTAssertEqual(data.panes[0].name, "Tab 1")
    }
}
