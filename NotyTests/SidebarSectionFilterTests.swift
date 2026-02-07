import XCTest
@testable import Noty

final class SidebarSectionFilterTests: XCTestCase {
    func testAllFilterAllowsEverySection() {
        for section in SidebarSectionFilter.allCases where section != .all {
            XCTAssertTrue(sidebarSectionFilterAllows(.all, section: section))
        }
    }

    func testSingleFilterAllowsOnlyMatchingSection() {
        XCTAssertTrue(sidebarSectionFilterAllows(.today, section: .today))
        XCTAssertFalse(sidebarSectionFilterAllows(.today, section: .pinned))
        XCTAssertFalse(sidebarSectionFilterAllows(.today, section: .folders))
    }
}
