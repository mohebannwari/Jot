import Foundation

struct NoteSelectionPolicy {
    static func resolveActiveNote(
        notes: [Note],
        currentActiveID: UUID?,
        selectedNoteIDs: Set<UUID>,
        selectionAnchorID: UUID?
    ) -> Note? {
        guard !notes.isEmpty else { return nil }

        if let currentActiveID,
           let current = notes.first(where: { $0.id == currentActiveID }) {
            return current
        }

        if let selectionAnchorID,
           selectedNoteIDs.contains(selectionAnchorID),
           let anchored = notes.first(where: { $0.id == selectionAnchorID }) {
            return anchored
        }

        if !selectedNoteIDs.isEmpty,
           let selected = notes.first(where: { selectedNoteIDs.contains($0.id) }) {
            return selected
        }

        return notes.max(by: { $0.date < $1.date })
    }
}
