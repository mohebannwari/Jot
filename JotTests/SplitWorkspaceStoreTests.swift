import XCTest
@testable import Jot

@MainActor
final class SplitWorkspaceStoreTests: XCTestCase {
    private let sessionsKey = "SplitSessionsData"
    private let activeIDKey = "ActiveSplitID"
    private let visibleKey = "IsSplitViewVisible"

    override func setUp() {
        super.setUp()
        clearPersistedSplitWorkspace()
    }

    override func tearDown() {
        clearPersistedSplitWorkspace()
        super.tearDown()
    }

    func testRestoreWaitsForInitialNotesBeforeReadingPersistedSessions() throws {
        let primary = note(id: UUID(), title: "Primary")
        let secondary = note(id: UUID(), title: "Secondary")
        let session = SplitSession(primaryNoteID: primary.id, secondaryNoteID: secondary.id)
        try persist(sessions: [session], activeID: session.id, isVisible: true)

        let store = SplitWorkspaceStore()
        let restoredNote = store.restore(
            availableNotes: [primary, secondary],
            hasLoadedInitialNotes: false
        )

        XCTAssertNil(restoredNote)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.activeID)
        XCTAssertFalse(store.isVisible)
    }

    func testRestoreKeepsCompleteSessionsWithExistingNotesAndSelectsActivePrimary() throws {
        let primary = note(id: UUID(), title: "Primary")
        let secondary = note(id: UUID(), title: "Secondary")
        let missing = UUID()
        let validSession = SplitSession(primaryNoteID: primary.id, secondaryNoteID: secondary.id)
        let invalidSession = SplitSession(primaryNoteID: primary.id, secondaryNoteID: missing)
        try persist(sessions: [invalidSession, validSession], activeID: validSession.id, isVisible: true)

        let store = SplitWorkspaceStore()
        let restoredNote = store.restore(
            availableNotes: [primary, secondary],
            hasLoadedInitialNotes: true
        )

        XCTAssertEqual(restoredNote?.id, primary.id)
        XCTAssertEqual(store.sessions, [validSession])
        XCTAssertEqual(store.activeID, validSession.id)
        XCTAssertTrue(store.isVisible)
        XCTAssertEqual(store.active?.primaryNoteID, primary.id)
    }

    func testPendingSplitLifecycleCompletesMovesAndClosesThroughStore() throws {
        let primaryID = UUID()
        let secondaryID = UUID()
        let replacementID = UUID()
        let store = SplitWorkspaceStore()

        store.createPendingSplit(position: .left, primaryNoteID: primaryID)
        let pendingIndex = try XCTUnwrap(store.activeIndex)
        store.sessions[pendingIndex].secondaryNoteID = secondaryID
        store.completePendingSplitIfNeeded(at: pendingIndex)

        XCTAssertNil(store.pendingID)
        XCTAssertEqual(store.active?.primaryNoteID, primaryID)
        XCTAssertEqual(store.active?.secondaryNoteID, secondaryID)
        XCTAssertEqual(store.active?.position, .left)

        let newPrimaryID = store.moveActiveToOtherSide()

        XCTAssertEqual(newPrimaryID, secondaryID)
        XCTAssertEqual(store.active?.primaryNoteID, secondaryID)
        XCTAssertEqual(store.active?.secondaryNoteID, primaryID)

        let createdNewSession = store.createOrReplaceActiveSplitFromDrop(
            primaryNoteID: primaryID,
            droppedNoteID: replacementID,
            position: .right
        )

        XCTAssertFalse(createdNewSession)
        XCTAssertEqual(store.active?.secondaryNoteID, replacementID)
        XCTAssertEqual(store.active?.position, .right)

        store.closeActiveSplit()

        XCTAssertNil(store.activeID)
        XCTAssertFalse(store.isVisible)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    private func note(id: UUID, title: String) -> Note {
        var note = Note(title: title, content: "")
        note.id = id
        return note
    }

    private func persist(sessions: [SplitSession], activeID: UUID, isVisible: Bool) throws {
        let data = try JSONEncoder().encode(sessions)
        UserDefaults.standard.set(data, forKey: sessionsKey)
        UserDefaults.standard.set(activeID.uuidString, forKey: activeIDKey)
        UserDefaults.standard.set(isVisible, forKey: visibleKey)
    }

    private func clearPersistedSplitWorkspace() {
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        UserDefaults.standard.removeObject(forKey: activeIDKey)
        UserDefaults.standard.removeObject(forKey: visibleKey)
    }
}
