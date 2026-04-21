//
//  SmartFolderPredicate+Evaluation.swift
//  Jot
//
//  Pure matching logic for smart folders — used by SimpleSwiftDataManager and tests.
//

import Foundation

enum JotContentAttachmentMarkers {
    /// Prefixes emitted by `NoteSerializer` for inline attachments (keep in sync with that pipeline).
    static let markupPrefixes: [String] = [
        "[[file|",
        "[[image|",
        "[[webclip|",
        "[[linkcard|",
        "[[filelink|",
    ]

    static func contentHasAttachmentMarkup(_ content: String) -> Bool {
        markupPrefixes.contains { content.contains($0) }
    }

    /// Checkbox lines serialize as `[ ]` or `[x]` (see `NoteSerializer`).
    static func contentHasChecklistMarkup(_ content: String) -> Bool {
        content.contains("[ ]") || content.contains("[x]")
    }
}

extension SmartFolderPredicate {

    /// Whether `note` satisfies every **enabled** criterion (AND).
    func matches(_ note: Note) -> Bool {
        guard hasAnyActiveCriterion else { return false }

        if let tags = requiredTags {
            let required = tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !required.isEmpty {
                let noteTagsLower = Set(note.tags.map { $0.lowercased() })
                for t in required {
                    if !noteTagsLower.contains(t.lowercased()) {
                        return false
                    }
                }
            }
        }

        if let field = dateField, dateStart != nil || dateEnd != nil {
            let value = field == .created ? note.createdAt : note.date
            if let start = dateStart, value < start {
                return false
            }
            if let end = dateEnd, value > end {
                return false
            }
        }

        if let k = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
            let haystack = "\(note.title) \(note.content)"
            if haystack.range(of: k, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
        }

        if requirePinned == true, !note.isPinned {
            return false
        }
        if requireLocked == true, !note.isLocked {
            return false
        }
        if requireHasAttachments == true, !JotContentAttachmentMarkers.contentHasAttachmentMarkup(note.content) {
            return false
        }
        if requireHasChecklist == true, !JotContentAttachmentMarkers.contentHasChecklistMarkup(note.content) {
            return false
        }

        return true
    }

    /// Counts matches in `notes` (full list, typically active notes).
    func matchCount(in notes: [Note]) -> Int {
        notes.reduce(0) { $0 + (matches($1) ? 1 : 0) }
    }
}
