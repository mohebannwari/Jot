import Foundation

enum SidebarExpansionReducer {
    static func collapseAll(
        expandedFolderIDs: inout Set<UUID>,
        showAllNotesFolderIDs: inout Set<UUID>,
        expandedSmartFolderIDs: inout Set<UUID>,
        showAllNotesSmartFolderIDs: inout Set<UUID>
    ) {
        expandedFolderIDs.removeAll()
        showAllNotesFolderIDs.removeAll()
        expandedSmartFolderIDs.removeAll()
        showAllNotesSmartFolderIDs.removeAll()
    }

    static func markFolderExpanded(
        _ folderID: UUID,
        expandedFolderIDs: inout Set<UUID>,
        showAllNotesFolderIDs: inout Set<UUID>,
        showAllNotes: Bool = false
    ) {
        expandedFolderIDs.insert(folderID)
        if showAllNotes {
            showAllNotesFolderIDs.insert(folderID)
        }
    }
}
