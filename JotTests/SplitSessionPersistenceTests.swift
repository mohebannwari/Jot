import XCTest
@testable import Jot

@MainActor
final class SplitSessionPersistenceTests: XCTestCase {
    func testSplitSessionCodableRoundTripPreservesPaneIDsPositionAndRatio() throws {
        let sessionID = UUID()
        let primaryID = UUID()
        let secondaryID = UUID()
        var session = SplitSession(
            id: sessionID,
            primaryNoteID: primaryID,
            secondaryNoteID: secondaryID
        )
        session.position = .left
        session.ratio = 0.37

        let data = try JSONEncoder().encode([session])
        let decoded = try JSONDecoder().decode([SplitSession].self, from: data)

        XCTAssertEqual(decoded, [session])
        XCTAssertEqual(decoded.first?.id, sessionID)
        XCTAssertEqual(decoded.first?.primaryNoteID, primaryID)
        XCTAssertEqual(decoded.first?.secondaryNoteID, secondaryID)
        XCTAssertEqual(decoded.first?.position, .left)
        XCTAssertEqual(Double(try XCTUnwrap(decoded.first?.ratio)), 0.37, accuracy: 0.0001)
        XCTAssertEqual(decoded.first?.isComplete, true)
    }

    func testSplitSessionIncompleteStateSurvivesDecodeButRemainsIncomplete() throws {
        let session = SplitSession(primaryNoteID: UUID(), secondaryNoteID: nil)

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SplitSession.self, from: data)

        XCTAssertEqual(decoded.primaryNoteID, session.primaryNoteID)
        XCTAssertNil(decoded.secondaryNoteID)
        XCTAssertEqual(decoded.position, .right)
        XCTAssertEqual(decoded.ratio, 0.5, accuracy: 0.0001)
        XCTAssertFalse(decoded.isComplete)
    }
}
