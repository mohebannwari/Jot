import XCTest
@testable import Jot

@MainActor
final class MeetingNotesCapabilityTests: XCTestCase {

    override func tearDown() {
        AppleIntelligenceService.shared.setTestingAvailabilityOverride(nil)
        super.tearDown()
    }

    func testMeetingNotesCapabilityDisablesEntryPointsWhenUnavailable() {
        AppleIntelligenceService.shared.setTestingAvailabilityOverride(
            AppleIntelligenceAvailabilitySnapshot(
                isAvailable: false,
                unavailabilityReason: "Apple Intelligence model is downloading. Try again shortly."
            )
        )

        let capability = AppleIntelligenceService.shared.refreshMeetingNotesCapability()

        XCTAssertFalse(capability.canStartNewSession)
        XCTAssertFalse(capability.showsEntryPoints)
        XCTAssertFalse(capability.registersGlobalHotKey)
        XCTAssertEqual(
            capability.unavailabilityReason,
            "Apple Intelligence model is downloading. Try again shortly."
        )
    }

    func testMeetingNotesCapabilityEnablesEntryPointsWhenAvailable() {
        AppleIntelligenceService.shared.setTestingAvailabilityOverride(
            AppleIntelligenceAvailabilitySnapshot(isAvailable: true, unavailabilityReason: "")
        )

        let capability = AppleIntelligenceService.shared.refreshMeetingNotesCapability()

        XCTAssertTrue(capability.canStartNewSession)
        XCTAssertTrue(capability.showsEntryPoints)
        XCTAssertTrue(capability.registersGlobalHotKey)
        XCTAssertEqual(capability.unavailabilityReason, "")
    }

    func testMeetingRecorderManagerDoesNotStartWhenAppleIntelligenceIsUnavailable() {
        AppleIntelligenceService.shared.setTestingAvailabilityOverride(
            AppleIntelligenceAvailabilitySnapshot(
                isAvailable: false,
                unavailabilityReason: "Apple Intelligence requires Apple Silicon."
            )
        )

        let manager = MeetingRecorderManager()
        manager.startRecording(for: UUID())

        XCTAssertEqual(manager.recordingState, .idle)
        XCTAssertNil(manager.recordingNoteID)
    }
}
