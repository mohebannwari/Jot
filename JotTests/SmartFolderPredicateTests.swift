import XCTest
@testable import Jot

final class SmartFolderPredicateTests: XCTestCase {

    private func note(
        title: String = "T",
        content: String = "",
        tags: [String] = [],
        isPinned: Bool = false,
        isLocked: Bool = false,
        createdAt: Date = Date(),
        modified: Date = Date()
    ) -> Note {
        var n = Note(title: title, content: content, tags: tags, isPinned: isPinned, isLocked: isLocked)
        n.createdAt = createdAt
        n.date = modified
        return n
    }

    func testTagsAllRequiredCaseInsensitive() {
        var p = SmartFolderPredicate()
        p.requiredTags = ["Work", "IDEAS"]
        let n = note(tags: ["work", "ideas"])
        XCTAssertTrue(p.matches(n))
        XCTAssertFalse(p.matches(note(tags: ["work"])))
    }

    func testKeywordInTitleOrContent() {
        var p = SmartFolderPredicate()
        p.keyword = "alpha"
        XCTAssertTrue(p.matches(note(title: "Alpha note", content: "")))
        XCTAssertTrue(p.matches(note(title: "x", content: "has alpha here")))
        XCTAssertFalse(p.matches(note(title: "Beta", content: "gamma")))
    }

    func testPinnedAndLocked() {
        var p = SmartFolderPredicate()
        p.requirePinned = true
        XCTAssertTrue(p.matches(note(isPinned: true)))
        XCTAssertFalse(p.matches(note(isPinned: false)))

        p = SmartFolderPredicate()
        p.requireLocked = true
        XCTAssertTrue(p.matches(note(isLocked: true)))
        XCTAssertFalse(p.matches(note(isLocked: false)))
    }

    func testAttachmentMarkers() {
        var p = SmartFolderPredicate()
        p.requireHasAttachments = true
        XCTAssertTrue(p.matches(note(content: "x [[image|||f.png]]")))
        XCTAssertTrue(p.matches(note(content: "[[file|t|a|b]]")))
        XCTAssertFalse(p.matches(note(content: "plain")))
    }

    func testChecklistMarkers() {
        var p = SmartFolderPredicate()
        p.requireHasChecklist = true
        XCTAssertTrue(p.matches(note(content: "todo [ ]")))
        XCTAssertTrue(p.matches(note(content: "done [x]")))
        XCTAssertFalse(p.matches(note(content: "no box")))
    }

    func testDateRangeCreated() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 2_000_000)
        var p = SmartFolderPredicate()
        p.dateField = .created
        p.dateStart = start
        p.dateEnd = end
        XCTAssertTrue(p.matches(note(createdAt: Date(timeIntervalSince1970: 1_500_000))))
        XCTAssertFalse(p.matches(note(createdAt: Date(timeIntervalSince1970: 500_000))))
    }

    func testDateRangeModified() {
        let start = Date(timeIntervalSince1970: 3_000_000)
        let end = Date(timeIntervalSince1970: 4_000_000)
        var p = SmartFolderPredicate()
        p.dateField = .modified
        p.dateStart = start
        p.dateEnd = end
        XCTAssertTrue(p.matches(note(modified: Date(timeIntervalSince1970: 3_500_000))))
        XCTAssertFalse(p.matches(note(modified: Date(timeIntervalSince1970: 5_000_000))))
    }

    func testANDSemantics() {
        var p = SmartFolderPredicate()
        p.requiredTags = ["a"]
        p.requirePinned = true
        XCTAssertTrue(p.matches(note(tags: ["a"], isPinned: true)))
        XCTAssertFalse(p.matches(note(tags: ["a"], isPinned: false)))
        XCTAssertFalse(p.matches(note(tags: ["b"], isPinned: true)))
    }

    func testHasAnyActiveCriterion() {
        XCTAssertFalse(SmartFolderPredicate().hasAnyActiveCriterion)
        var p = SmartFolderPredicate()
        p.keyword = "x"
        XCTAssertTrue(p.hasAnyActiveCriterion)
    }

    func testMatchCount() {
        var p = SmartFolderPredicate()
        p.requirePinned = true
        let notes = [note(isPinned: true), note(isPinned: true), note(isPinned: false)]
        XCTAssertEqual(p.matchCount(in: notes), 2)
    }
}
