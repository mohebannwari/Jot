import XCTest
@testable import Jot

final class AIGeneratedTagSanitizationTests: XCTestCase {
    func testTrimsDeduplicatesAndCapsAtThree() {
        let s = AIGeneratedTagSanitization.sanitize(
            suggested: ["  a  ", "A", "b", "c", "d"],
            userTags: []
        )
        XCTAssertEqual(s, ["a", "b", "c"])
    }

    func testRespectsUserTagsCaseInsensitive() {
        let s = AIGeneratedTagSanitization.sanitize(
            suggested: ["Work", "work", "Ideas", "play"],
            userTags: ["WORK", "play"]
        )
        XCTAssertEqual(s, ["Ideas"])
    }
}
