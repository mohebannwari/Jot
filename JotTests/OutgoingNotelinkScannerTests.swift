import XCTest
@testable import Jot

final class OutgoingNotelinkScannerTests: XCTestCase {

    private let sampleID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
    private let otherID = UUID(uuidString: "223E4567-E89B-12D3-A456-426614174001")!

    func testParsesValidNotelink() {
        let content = "Hello [[notelink|\(sampleID.uuidString)|My Note]] tail"
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].noteID, sampleID)
        XCTAssertEqual(out[0].serializedTitle, "My Note")
    }

    func testTitleMayContainPipe() {
        let content = "[[notelink|\(sampleID.uuidString)|A|B|C]]"
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].serializedTitle, "A|B|C")
    }

    func testDedupesByNoteIDPreservesOrder() {
        let content = """
        [[notelink|\(sampleID.uuidString)|First]]
        [[notelink|\(otherID.uuidString)|Other]]
        [[notelink|\(sampleID.uuidString)|Second]]
        """
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].noteID, sampleID)
        XCTAssertEqual(out[0].serializedTitle, "First")
        XCTAssertEqual(out[1].noteID, otherID)
    }

    func testSkipsInvalidUUID() {
        let content = "[[notelink|not-a-uuid|Title]] [[notelink|\(sampleID.uuidString)|Ok]]"
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].noteID, sampleID)
    }

    func testExcludingNoteIDFiltersSelfMention() {
        let content = "[[notelink|\(sampleID.uuidString)|Self]]"
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content, excludingNoteID: sampleID)
        XCTAssertTrue(out.isEmpty)
    }

    func testMalformedMissingClosingBracketDoesNotHang() {
        let content = "[[notelink|\(sampleID.uuidString)|No close"
        let out = OutgoingNotelinkScanner.outgoingNotelinks(in: content)
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - removingNotelinks

    func testRemovingNotelinksStripsMatchingTarget() {
        let content = "Hello [[notelink|\(sampleID.uuidString)|My Note]] tail"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID], from: content)
        XCTAssertEqual(out, "Hello  tail")
    }

    func testRemovingNotelinksTitleMayContainPipe() {
        let content = "X [[notelink|\(sampleID.uuidString)|A|B|C]] Y"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID], from: content)
        XCTAssertEqual(out, "X  Y")
    }

    func testRemovingNotelinksMultipleTokensAndTargets() {
        let content =
            "[[notelink|\(sampleID.uuidString)|First]]\n[[notelink|\(otherID.uuidString)|Other]]\nend"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID, otherID], from: content)
        XCTAssertEqual(out, "\n\nend")
    }

    func testRemovingNotelinksLeavesOtherTarget() {
        let content = "[[notelink|\(sampleID.uuidString)|A]] [[notelink|\(otherID.uuidString)|B]]"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID], from: content)
        XCTAssertEqual(out, " [[notelink|\(otherID.uuidString)|B]]")
    }

    func testRemovingNotelinksEmptyRemovedSetReturnsOriginal() {
        let content = "[[notelink|\(sampleID.uuidString)|X]]"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [], from: content)
        XCTAssertEqual(out, content)
    }

    func testRemovingNotelinksLeavesInvalidUUIDToken() {
        let content = "[[notelink|not-a-uuid|Title]]"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID], from: content)
        XCTAssertEqual(out, content)
    }

    func testRemovingNotelinksUnclosedPreservesTail() {
        let content = "pre [[notelink|\(sampleID.uuidString)|No close"
        let out = OutgoingNotelinkScanner.removingNotelinks(targeting: [sampleID], from: content)
        XCTAssertEqual(out, content)
    }
}
