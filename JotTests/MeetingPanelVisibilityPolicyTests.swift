import XCTest
@testable import Jot

final class MeetingPanelVisibilityPolicyTests: XCTestCase {
    func testActiveSessionForVisibleNoteShowsPanelAcrossNonIdleStates() {
        let noteID = UUID()

        for state in [
            MeetingRecordingState.recording,
            .paused,
            .processing,
            .complete
        ] {
            XCTAssertTrue(
                MeetingPanelVisibilityPolicy.shouldShow(
                    recordingNoteID: noteID,
                    recordingState: state,
                    visibleNoteID: noteID
                ),
                "Expected panel visible for state \(state)"
            )
        }
    }

    func testIdleOrDifferentVisibleNoteHidesPanel() {
        let recordingNoteID = UUID()
        let otherNoteID = UUID()

        XCTAssertFalse(
            MeetingPanelVisibilityPolicy.shouldShow(
                recordingNoteID: recordingNoteID,
                recordingState: .idle,
                visibleNoteID: recordingNoteID
            )
        )

        XCTAssertFalse(
            MeetingPanelVisibilityPolicy.shouldShow(
                recordingNoteID: recordingNoteID,
                recordingState: .recording,
                visibleNoteID: otherNoteID
            )
        )

        XCTAssertFalse(
            MeetingPanelVisibilityPolicy.shouldShow(
                recordingNoteID: nil,
                recordingState: .recording,
                visibleNoteID: recordingNoteID
            )
        )
    }

    func testSplitCollapseRemountForRecordingNoteShowsPanel() {
        let splitPrimaryNoteID = UUID()
        let splitRecordingNoteID = UUID()

        XCTAssertTrue(
            MeetingPanelVisibilityPolicy.shouldShow(
                recordingNoteID: splitRecordingNoteID,
                recordingState: .recording,
                visibleNoteID: splitRecordingNoteID
            )
        )

        XCTAssertFalse(
            MeetingPanelVisibilityPolicy.shouldShow(
                recordingNoteID: splitRecordingNoteID,
                recordingState: .recording,
                visibleNoteID: splitPrimaryNoteID
            )
        )
    }
}
