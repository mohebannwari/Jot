//
//  SimpleSwiftDataManager+NotelinkCleanup.swift
//  Jot
//
//  When notes are deleted (trash, permanent delete, discard, empty trash), removes
//  `[[notelink|<uuid>|…]]` tokens pointing at those UUIDs from every surviving note.
//  Restoring a trashed note does not restore mentions stripped from other notes — tokens are gone.
//

import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {

    /// Strips outgoing notelinks to any UUID in `removedTargetIDs` from all non-deleted notes,
    /// persists, patches `notes` / `archivedNotes`, reindexes Spotlight, and notifies the UI.
    func stripOutgoingNotelinksForRemovedNoteIDs(_ removedTargetIDs: Set<UUID>) {
        guard !removedTargetIDs.isEmpty else { return }

        do {
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == false }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let survivors = try modelContext.fetch(descriptor)

            var affectedSourceNoteIDs = Set<UUID>()
            var changed = false

            for entity in survivors {
                let newContent = OutgoingNotelinkScanner.removingNotelinks(
                    targeting: removedTargetIDs,
                    from: entity.content
                )
                guard newContent != entity.content else { continue }
                entity.updateContent(newContent)
                affectedSourceNoteIDs.insert(entity.id)
                changed = true
            }

            guard changed else { return }

            try modelContext.save()

            for entity in survivors where affectedSourceNoteIDs.contains(entity.id) {
                patchInMemoryNoteAfterNotelinkStrip(entity: entity)
                SpotlightIndexer.shared.indexNote(entity.toNote())
            }

            NotificationCenter.default.post(
                name: .jotOutgoingNotelinksRemoved,
                object: nil,
                userInfo: [
                    "removedTargetIDs": removedTargetIDs.map(\.uuidString),
                    "affectedSourceNoteIDs": affectedSourceNoteIDs.map(\.uuidString),
                ]
            )

            logger.info(
                "Stripped outgoing notelinks to \(removedTargetIDs.count) removed note(s); updated \(affectedSourceNoteIDs.count) source note(s)"
            )
        } catch {
            logger.error("stripOutgoingNotelinksForRemovedNoteIDs failed: \(error)")
        }
    }

    /// Merges `entity.toNote()` into `notes` or `archivedNotes` like a content-only save.
    private func patchInMemoryNoteAfterNotelinkStrip(entity: NoteEntity) {
        let id = entity.id
        var updated = entity.toNote()

        if let index = notes.firstIndex(where: { $0.id == id }) {
            let existing = notes[index]
            updated.isPinned = existing.isPinned
            updated.isLocked = existing.isLocked
            updated.folderID = existing.folderID
            updated.tags = existing.tags
            updated.aiGeneratedTags = existing.aiGeneratedTags
            updated.stickers = existing.stickers
            suppressDerivedRecompute = true
            notes[index] = updated
            suppressDerivedRecompute = false
            updateNoteInDerivedCollections(updated)
        } else if let index = archivedNotes.firstIndex(where: { $0.id == id }) {
            let existing = archivedNotes[index]
            updated.isPinned = existing.isPinned
            updated.isLocked = existing.isLocked
            updated.folderID = existing.folderID
            updated.tags = existing.tags
            updated.aiGeneratedTags = existing.aiGeneratedTags
            updated.stickers = existing.stickers
            archivedNotes[index] = updated
        }
    }
}
