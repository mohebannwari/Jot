import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    // MARK: - Archive Operations

    @discardableResult
    func archiveNotes(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { idArray.contains($0.id) && $0.isArchived == false }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toArchive = try modelContext.fetch(descriptor)

            guard !toArchive.isEmpty else {
                logger.warning("No matching unarchived notes found for batch archive")
                return 0
            }

            for entity in toArchive {
                entity.isArchived = true
                entity.modifiedAt = Date()
            }

            try modelContext.save()
            notes.removeAll { ids.contains($0.id) }
            loadArchivedNotes()
            SpotlightIndexer.shared.deindexNotes(ids: ids)
            logger.info("Archived \(toArchive.count) notes in batch")
            return toArchive.count
        } catch {
            logger.error("Failed to batch archive notes: \(error)")
            return 0
        }
    }

    @discardableResult
    func unarchiveNotes(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { $0.isArchived == true && idArray.contains($0.id) }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toUnarchive = try modelContext.fetch(descriptor)

            guard !toUnarchive.isEmpty else {
                logger.warning("No matching archived notes found for batch unarchive")
                return 0
            }

            for entity in toUnarchive {
                entity.isArchived = false
                entity.modifiedAt = Date()
            }

            try modelContext.save()
            archivedNotes.removeAll { ids.contains($0.id) }
            loadNotes()
            // Re-index unarchived notes in Spotlight
            for entity in toUnarchive {
                SpotlightIndexer.shared.indexNote(entity.toNote())
            }
            logger.info("Unarchived \(toUnarchive.count) notes in batch")
            return toUnarchive.count
        } catch {
            logger.error("Failed to batch unarchive notes: \(error)")
            return 0
        }
    }

    // MARK: - Trash Operations

    func loadDeletedNotes() {
        do {
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true }
            var descriptor = FetchDescriptor<NoteEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
            )
            descriptor.fetchLimit = maxLoadLimit
            let fetched = try modelContext.fetch(descriptor).map { $0.toNote() }
            deletedNotes = fetched
            logger.info("Loaded \(fetched.count) deleted notes")
        } catch {
            logger.error("Failed to load deleted notes: \(error)")
            deletedNotes = []
        }
    }

    @discardableResult
    func moveToTrash(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { idArray.contains($0.id) && $0.isDeleted == false }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toTrash = try modelContext.fetch(descriptor)

            guard !toTrash.isEmpty else {
                logger.warning("No matching notes found for move to trash")
                return 0
            }

            stripOutgoingNotelinksForRemovedNoteIDs(Set(toTrash.map(\.id)))

            let now = Date()
            for entity in toTrash {
                entity.isDeleted = true
                entity.deletedDate = now
                entity.modifiedAt = now
            }

            try modelContext.save()
            notes.removeAll { ids.contains($0.id) }
            archivedNotes.removeAll { ids.contains($0.id) }
            loadDeletedNotes()
            SpotlightIndexer.shared.deindexNotes(ids: ids)
            logger.info("Moved \(toTrash.count) notes to trash")
            return toTrash.count
        } catch {
            logger.error("Failed to move notes to trash: \(error)")
            return 0
        }
    }

    @discardableResult
    func restoreFromTrash(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true && idArray.contains($0.id) }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toRestore = try modelContext.fetch(descriptor)

            guard !toRestore.isEmpty else {
                logger.warning("No matching deleted notes found for restore")
                return 0
            }

            for entity in toRestore {
                entity.isDeleted = false
                entity.deletedDate = nil
                entity.modifiedAt = Date()
            }

            try modelContext.save()
            deletedNotes.removeAll { ids.contains($0.id) }
            loadNotes()
            // Re-index restored notes in Spotlight
            for entity in toRestore {
                SpotlightIndexer.shared.indexNote(entity.toNote())
            }
            logger.info("Restored \(toRestore.count) notes from trash")
            return toRestore.count
        } catch {
            logger.error("Failed to restore notes from trash: \(error)")
            return 0
        }
    }

    @discardableResult
    func permanentlyDeleteNotes(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true && idArray.contains($0.id) }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toDelete = try modelContext.fetch(descriptor)

            guard !toDelete.isEmpty else {
                logger.warning("No matching deleted notes found for permanent delete")
                return 0
            }

            stripOutgoingNotelinksForRemovedNoteIDs(Set(toDelete.map(\.id)))

            for entity in toDelete {
                modelContext.delete(entity)
            }

            try modelContext.save()
            deletedNotes.removeAll { ids.contains($0.id) }
            SpotlightIndexer.shared.deindexNotes(ids: ids)
            logger.info("Permanently deleted \(toDelete.count) notes")

            // Clean up orphaned images and file attachments after permanent deletion
            triggerStorageCleanup()

            return toDelete.count
        } catch {
            logger.error("Failed to permanently delete notes: \(error)")
            return 0
        }
    }

    func emptyTrash() {
        do {
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            stripOutgoingNotelinksForRemovedNoteIDs(Set(entities.map(\.id)))

            for entity in entities {
                modelContext.delete(entity)
            }

            try modelContext.save()
            deletedNotes.removeAll()
            logger.info("Emptied trash (\(entities.count) notes)")

            // Clean up orphaned images and file attachments after emptying trash
            triggerStorageCleanup()
        } catch {
            logger.error("Failed to empty trash: \(error)")
        }
    }

    /// Run image and file attachment cleanup against all remaining notes.
    /// Uses lightweight content-only fetch to avoid hydrating full Note objects.
    private func triggerStorageCleanup() {
        // Capture content strings on the main actor, then clean up
        let allNotes: [Note]
        do {
            allNotes = try self.modelContext.fetch(FetchDescriptor<NoteEntity>()).map { $0.toNote() }
        } catch {
            self.logger.error("triggerStorageCleanup: failed to fetch notes — \(error)")
            return
        }
        ImageStorageManager.shared.cleanupUnusedImages(referencedInNotes: allNotes)
        FileAttachmentStorageManager.shared.cleanupUnusedFiles(referencedInNotes: allNotes)
    }

    func restoreAllFromTrash() {
        do {
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            for entity in entities {
                entity.isDeleted = false
                entity.deletedDate = nil
                entity.modifiedAt = Date()
            }

            try modelContext.save()
            deletedNotes.removeAll()
            loadNotes()
            logger.info("Restored all \(entities.count) notes from trash")
        } catch {
            logger.error("Failed to restore all from trash: \(error)")
        }
    }

}
