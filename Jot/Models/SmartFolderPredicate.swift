//
//  SmartFolderPredicate.swift
//  Jot
//
//  Saved filter for smart folders. Optional fields with nil = criterion disabled.
//  Multiple enabled criteria combine with AND semantics.
//

import Foundation

enum SmartFolderDateField: String, Codable, CaseIterable, Sendable {
    case created
    case modified
}

struct SmartFolderPredicate: Codable, Equatable, Sendable {
    /// Note must include every tag (case-insensitive). Empty or nil = off.
    var requiredTags: [String]?

    /// Which timestamp to compare when the date filter is active.
    var dateField: SmartFolderDateField?

    /// Inclusive range; both nil with a set `dateField` means the date filter is off.
    var dateStart: Date?
    var dateEnd: Date?

    /// Substring match on title + content (case-insensitive). nil or blank = off.
    var keyword: String?

    /// When true, note must be pinned. nil = do not filter on pin.
    var requirePinned: Bool?

    /// When true, note must be locked.
    var requireLocked: Bool?

    /// When true, note content must contain Jot attachment markup.
    var requireHasAttachments: Bool?

    /// When true, note must contain checkbox tokens (`[ ]` / `[x]`).
    var requireHasChecklist: Bool?

    /// True if at least one filter criterion is enabled (used to reject empty smart folders).
    var hasAnyActiveCriterion: Bool {
        if let tags = requiredTags {
            let trimmed = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !trimmed.isEmpty { return true }
        }
        if let field = dateField, dateStart != nil || dateEnd != nil {
            _ = field
            return true
        }
        if let k = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
            return true
        }
        if requirePinned == true { return true }
        if requireLocked == true { return true }
        if requireHasAttachments == true { return true }
        if requireHasChecklist == true { return true }
        return false
    }
}
