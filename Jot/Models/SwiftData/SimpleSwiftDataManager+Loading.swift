import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    // MARK: - Basic Operations

    private func fetchNotesFromStore(limit: Int? = nil) throws -> [Note] {
        let predicate = #Predicate<NoteEntity> { $0.isArchived == false && $0.isDeleted == false }
        var descriptor = FetchDescriptor<NoteEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor).map { $0.toNote() }
    }

    func loadNotes(isInitialLoad: Bool = false) {
        Task { @MainActor in
            defer {
                if isInitialLoad {
                    self.markInitialNotesLoaded()
                }
            }
            do {
                let predicate = #Predicate<NoteEntity> { $0.isArchived == false && $0.isDeleted == false }
                var descriptor = FetchDescriptor<NoteEntity>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                )
                descriptor.fetchLimit = self.maxLoadLimit
                self.notes = try modelContext.fetch(descriptor).map { $0.toNote() }
                logger.info("Loaded \(self.notes.count) notes from SwiftData (limited to \(self.maxLoadLimit))")
            } catch {
                logger.error("Failed to load notes: \(error)")
                self.notes = []
            }

            if isInitialLoad && self.notes.count >= self.maxLoadLimit {
                // Initial load hit the cap — load remaining notes in the background
                Task { @MainActor in
                    self.loadMoreNotes(offset: self.maxLoadLimit)
                }
            }

            if isInitialLoad {
                // Fire-and-forget: clean up orphaned images after initial load.
                // Fetches all notes (active + archived + deleted) so no referenced
                // image is incorrectly removed.
                Task { @MainActor in
                    let allNotes: [Note]
                    do {
                        allNotes = try self.modelContext.fetch(FetchDescriptor<NoteEntity>()).map { $0.toNote() }
                    } catch {
                        self.logger.error("cleanupUnusedImages: failed to fetch all notes — \(error)")
                        return
                    }
                    ImageStorageManager.shared.cleanupUnusedImages(referencedInNotes: allNotes)
                    FileAttachmentStorageManager.shared.cleanupUnusedFiles(referencedInNotes: allNotes)
                    let contents = allNotes.map { $0.content }
                    ThumbnailCache.shared.cleanupOrphanedThumbnails(activeNoteContents: contents)
                }
            }
        }
    }

    /// Lightweight check that populates archivedNotes/archivedFolders only if
    /// the database has archived items but the arrays haven't been loaded yet.
    func checkForArchivedItems() {
        do {
            let notePredicate = #Predicate<NoteEntity> { $0.isArchived == true && $0.isDeleted == false }
            let noteDescriptor = FetchDescriptor<NoteEntity>(predicate: notePredicate)
            let folderPredicate = #Predicate<FolderEntity> { $0.isArchived == true }
            let folderDescriptor = FetchDescriptor<FolderEntity>(predicate: folderPredicate)

            if archivedNotes.isEmpty, (try modelContext.fetchCount(noteDescriptor)) > 0 {
                loadArchivedNotes()
            }
            if archivedFolders.isEmpty, (try modelContext.fetchCount(folderDescriptor)) > 0 {
                loadArchivedFolders()
            }
        } catch {
            logger.error("Failed to check for archived items: \(error)")
        }
    }

    func loadArchivedNotes() {
        do {
            let predicate = #Predicate<NoteEntity> { $0.isArchived == true && $0.isDeleted == false }
            var descriptor = FetchDescriptor<NoteEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
            )
            descriptor.fetchLimit = maxLoadLimit
            let fetched = try modelContext.fetch(descriptor).map { $0.toNote() }
            archivedNotes = fetched
            logger.info("Loaded \(fetched.count) archived notes")
        } catch {
            logger.error("Failed to load archived notes: \(error)")
            archivedNotes = []
        }
    }

}
