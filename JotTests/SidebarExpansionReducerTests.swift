import XCTest
@testable import Jot

final class SidebarExpansionReducerTests: XCTestCase {
    func testCollapseAllClearsFolderAndSmartFolderExpansionState() {
        var expandedFolderIDs: Set<UUID> = [UUID()]
        var showAllNotesFolderIDs: Set<UUID> = [UUID()]
        var expandedSmartFolderIDs: Set<UUID> = [UUID()]
        var showAllNotesSmartFolderIDs: Set<UUID> = [UUID()]

        SidebarExpansionReducer.collapseAll(
            expandedFolderIDs: &expandedFolderIDs,
            showAllNotesFolderIDs: &showAllNotesFolderIDs,
            expandedSmartFolderIDs: &expandedSmartFolderIDs,
            showAllNotesSmartFolderIDs: &showAllNotesSmartFolderIDs
        )

        XCTAssertTrue(expandedFolderIDs.isEmpty)
        XCTAssertTrue(showAllNotesFolderIDs.isEmpty)
        XCTAssertTrue(expandedSmartFolderIDs.isEmpty)
        XCTAssertTrue(showAllNotesSmartFolderIDs.isEmpty)
    }

    func testMarkFolderExpandedCanAlsoEnableShowAllNotes() {
        let folderID = UUID()
        var expandedFolderIDs: Set<UUID> = []
        var showAllNotesFolderIDs: Set<UUID> = []

        SidebarExpansionReducer.markFolderExpanded(
            folderID,
            expandedFolderIDs: &expandedFolderIDs,
            showAllNotesFolderIDs: &showAllNotesFolderIDs,
            showAllNotes: true
        )

        XCTAssertEqual(expandedFolderIDs, [folderID])
        XCTAssertEqual(showAllNotesFolderIDs, [folderID])
    }
}
