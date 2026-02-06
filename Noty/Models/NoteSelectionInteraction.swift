import Foundation

enum NoteSelectionInteraction {
    case plain
    case commandToggle
    case shiftRange
}

struct NoteSelectionReducer {
    static func apply(
        interaction: NoteSelectionInteraction,
        noteID: UUID,
        currentSelection: Set<UUID>,
        currentAnchor: UUID?,
        orderedVisibleNoteIDs: [UUID]
    ) -> (selection: Set<UUID>, anchor: UUID?) {
        switch interaction {
        case .plain:
            return ([noteID], noteID)
        case .commandToggle:
            var selection = currentSelection
            if selection.contains(noteID) {
                selection.remove(noteID)
            } else {
                selection.insert(noteID)
            }
            return (selection, noteID)
        case .shiftRange:
            let anchor = resolveAnchor(currentAnchor: currentAnchor, currentSelection: currentSelection, fallback: noteID)
            let range = inclusiveRange(from: anchor, to: noteID, orderedVisibleNoteIDs: orderedVisibleNoteIDs)
            if range.isEmpty {
                return ([noteID], anchor)
            }
            return (Set(range), anchor)
        }
    }

    static func selectAll(orderedVisibleNoteIDs: [UUID]) -> Set<UUID> {
        Set(orderedVisibleNoteIDs)
    }

    static func inclusiveRange(from anchor: UUID, to noteID: UUID, orderedVisibleNoteIDs: [UUID]) -> [UUID] {
        guard
            let anchorIndex = orderedVisibleNoteIDs.firstIndex(of: anchor),
            let noteIndex = orderedVisibleNoteIDs.firstIndex(of: noteID)
        else {
            return []
        }

        if anchorIndex <= noteIndex {
            return Array(orderedVisibleNoteIDs[anchorIndex...noteIndex])
        }

        return Array(orderedVisibleNoteIDs[noteIndex...anchorIndex])
    }

    private static func resolveAnchor(currentAnchor: UUID?, currentSelection: Set<UUID>, fallback: UUID) -> UUID {
        if let currentAnchor {
            return currentAnchor
        }

        if let selected = currentSelection.first {
            return selected
        }

        return fallback
    }
}
