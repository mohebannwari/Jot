import Foundation

enum MeetingPanelVisibilityPolicy {
    static func shouldShow(
        recordingNoteID: UUID?,
        recordingState: MeetingRecordingState,
        visibleNoteID: UUID
    ) -> Bool {
        recordingNoteID == visibleNoteID && recordingState != .idle
    }
}
