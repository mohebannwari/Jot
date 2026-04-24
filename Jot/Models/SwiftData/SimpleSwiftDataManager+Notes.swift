import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    func addNote(
        title: String = "Untitled",
        content: String = "",
        tags: [String] = [],
        folderID: UUID? = nil
    ) -> Note {
        let noteEntity = NoteEntity(title: title, content: content)
        noteEntity.folderID = folderID
        noteEntity.tags = tags
        if folderID != nil {
            noteEntity.isPinned = false
        }


        modelContext.insert(noteEntity)

        do {
            try modelContext.save()
            let note = noteEntity.toNote()
            notes.insert(note, at: 0)
            SpotlightIndexer.shared.indexNote(note)
            logger.info("Added note: \(title)")
            return note
        } catch {
            logger.error("Failed to add note: \(error)")
            // Return a temporary note for error handling
            return Note(title: title, content: content, tags: tags, folderID: folderID)
        }
    }

    func updateNote(_ updatedNote: Note) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == updatedNote.id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(updatedNote.id) not found for update")
                return
            }

            // Check if sidebar-relevant metadata changed before touching the entity,
            // so we can skip the expensive recomputeDerivedNotes() for content-only saves.
            let existingNote = notes.first(where: { $0.id == updatedNote.id })
            let metadataChanged = existingNote.map { existing in
                existing.isPinned != updatedNote.isPinned
                || existing.isLocked != updatedNote.isLocked
                || existing.folderID != updatedNote.folderID
            } ?? true

            noteEntity.updateTitle(updatedNote.title)
            noteEntity.updateContent(updatedNote.content)
            // Persist stickers — on encoding failure, revert in-memory stickers to match entity
            var stickerEncodingFailed = false
            if updatedNote.stickers.isEmpty {
                noteEntity.stickersData = nil
            } else {
                do {
                    noteEntity.stickersData = try Self.encoder.encode(updatedNote.stickers)
                } catch {
                    logger.error("Failed to encode stickers: \(error)")
                    stickerEncodingFailed = true
                }
            }
            // Preserve metadata from the authoritative local notes array — the editor's
            // noteForPersist may carry stale isPinned/isLocked/folderID values.
            noteEntity.folderID = existingNote?.folderID ?? updatedNote.folderID
            noteEntity.isPinned = existingNote?.isPinned ?? updatedNote.isPinned
            noteEntity.isLocked = existingNote?.isLocked ?? updatedNote.isLocked

            // Meeting notes
            noteEntity.isMeetingNote = updatedNote.isMeetingNote
            if !updatedNote.meetingSessions.isEmpty {
                noteEntity.meetingSessionsData = (try? Self.encoder.encode(updatedNote.meetingSessions)) ?? noteEntity.meetingSessionsData
                noteEntity.meetingTranscript = ""
                noteEntity.meetingSummary = ""
                noteEntity.meetingDuration = 0
                noteEntity.meetingLanguage = ""
                noteEntity.meetingManualNotes = ""
            } else {
                noteEntity.meetingSessionsData = nil
                noteEntity.meetingTranscript = updatedNote.meetingTranscript
                noteEntity.meetingSummary = updatedNote.meetingSummary
                noteEntity.meetingDuration = updatedNote.meetingDuration
                noteEntity.meetingLanguage = updatedNote.meetingLanguage
                noteEntity.meetingManualNotes = updatedNote.meetingManualNotes
            }
            // Tags are managed by updateTags() -- preserve existing entity tags
            // to prevent autosave from clobbering tags with a stale snapshot.
            // `aiGeneratedTags` is updated only via `updateAIGeneratedTags` — same preservation rule.

            try modelContext.save()

            // Update local array — skip the expensive recomputeDerivedNotes() for content-only saves
            if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                var localNote = updatedNote
                let existing = notes[index]
                localNote.isPinned = existing.isPinned
                localNote.isLocked = existing.isLocked
                localNote.folderID = existing.folderID
                localNote.tags = existing.tags
                localNote.aiGeneratedTags = existing.aiGeneratedTags
                // If sticker encoding failed, keep entity-consistent stickers in memory
                if stickerEncodingFailed {
                    localNote.stickers = existing.stickers
                }
                if !metadataChanged {
                    suppressDerivedRecompute = true
                    notes[index] = localNote
                    suppressDerivedRecompute = false
                    updateNoteInDerivedCollections(localNote)
                } else {
                    notes[index] = localNote
                }
            }

            logger.info("Updated note: \(updatedNote.title)")
            if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                SpotlightIndexer.shared.indexNote(notes[index])
            }

            // Schedule a debounced version snapshot
            NoteVersionManager.shared.scheduleSnapshot(for: updatedNote, in: modelContext)

        } catch {
            logger.error("Failed to update note: \(error)")
        }
    }

    /// Update only the tags field on a note, leaving content and all other fields untouched.
    /// Prevents stale-content overwrites when tags are edited while the editor has unsaved changes.
    func updateTags(id: UUID, tags: [String]) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for tag update")
                return
            }

            noteEntity.tags = tags
            try modelContext.save()

            // Replace the array element explicitly so @Published notifies subscribers (SearchEngine
            // snapshots `notes` from ContentView; in-place `notes[i].tags = …` is easy to miss).
            if let index = notes.firstIndex(where: { $0.id == id }) {
                var updated = notes[index]
                updated.tags = tags
                suppressDerivedRecompute = true
                notes[index] = updated
                suppressDerivedRecompute = false
                updateNoteInDerivedCollections(updated)
                SpotlightIndexer.shared.indexNote(updated)
            }

            logger.info("Updated tags for note: \(id)")
        } catch {
            logger.error("Failed to update tags: \(error)")
        }
    }

    /// Persists on-device–suggested tags only. Does not modify user `tags`.
    func updateAIGeneratedTags(id: UUID, tags: [String]) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for AI tag update")
                return
            }

            noteEntity.aiGeneratedTags = tags
            try modelContext.save()

            if let index = notes.firstIndex(where: { $0.id == id }) {
                var updated = notes[index]
                updated.aiGeneratedTags = tags
                suppressDerivedRecompute = true
                notes[index] = updated
                suppressDerivedRecompute = false
                updateNoteInDerivedCollections(updated)
                SpotlightIndexer.shared.indexNote(updated)
            }

            logger.info("Updated AI tags for note: \(id)")
        } catch {
            logger.error("Failed to update AI tags: \(error)")
        }
    }

    /// Silently remove a note without moving it to trash (e.g. discarding an empty untitled note).
    func discardNote(id: UUID) {
        do {
            let targetID = id
            let predicate = #Predicate<NoteEntity> { $0.id == targetID }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            if let entity = try modelContext.fetch(descriptor).first {
                stripOutgoingNotelinksForRemovedNoteIDs([targetID])
                modelContext.delete(entity)
                try modelContext.save()
            }
            notes.removeAll { $0.id == id }
            SpotlightIndexer.shared.deindexNotes(ids: [id])
        } catch {
            logger.error("Failed to discard note: \(error)")
        }
    }

    func deleteNote(id: UUID) {
        moveToTrash(ids: [id])
    }

    @discardableResult
    func deleteNotes(ids: Set<UUID>) -> Int {
        moveToTrash(ids: ids)
    }

    func toggleLock(id: UUID) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for toggle lock")
                return
            }

            noteEntity.isLocked.toggle()
            try modelContext.save()

            let updatedNote: Note
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isLocked.toggle()
                updatedNote = notes[index]
            } else {
                updatedNote = noteEntity.toNote()
            }

            SpotlightIndexer.shared.indexNote(updatedNote)

            logger.info("Toggled lock for note with ID: \(id)")

        } catch {
            logger.error("Failed to toggle lock: \(error)")
        }
    }

    func togglePin(id: UUID) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for toggle pin")
                return
            }

            if noteEntity.folderID != nil {
                logger.info("Ignoring pin toggle for note in folder: \(id)")
                return
            }

            noteEntity.isPinned.toggle()
            try modelContext.save()

            // Update local array
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isPinned.toggle()
            }

            logger.info("Toggled pin for note with ID: \(id)")

        } catch {
            logger.error("Failed to toggle pin: \(error)")
        }
    }

    func replaceAll(_ newNotes: [Note]) {
        do {
            // Delete all existing notes
            let descriptor = FetchDescriptor<NoteEntity>()
            let entities = try modelContext.fetch(descriptor)
            for entity in entities {
                modelContext.delete(entity)
            }

            // Add new notes
            for note in newNotes {
                let noteEntity = NoteEntity(from: note)

                modelContext.insert(noteEntity)
            }

            try modelContext.save()
            notes = newNotes
            logger.info("Replaced all notes with \(newNotes.count) new notes")

        } catch {
            logger.error("Failed to replace all notes: \(error)")
        }
    }

}
