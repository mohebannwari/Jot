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
}
