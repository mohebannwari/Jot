import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    // MARK: - Testing Helpers

    func clearAllData() throws {
        let noteDescriptor = FetchDescriptor<NoteEntity>()
        let noteEntities = try modelContext.fetch(noteDescriptor)
        for note in noteEntities {
            modelContext.delete(note)
        }

        let folderDescriptor = FetchDescriptor<FolderEntity>()
        let folderEntities = try modelContext.fetch(folderDescriptor)
        for folder in folderEntities {
            modelContext.delete(folder)
        }

        let smartFolderDescriptor = FetchDescriptor<SmartFolderEntity>()
        for entity in try modelContext.fetch(smartFolderDescriptor) {
            modelContext.delete(entity)
        }

        try modelContext.save()
        notes.removeAll()
        folders.removeAll()
        smartFolders.removeAll()
        notesBySmartFolderID = [:]

        logger.info("Cleared all SwiftData")
    }

    // MARK: - Memory Management

    func loadMoreNotes(offset: Int = 0) {
        var currentOffset = offset
        do {
            let predicate = #Predicate<NoteEntity> {
                $0.isArchived == false && $0.isDeleted == false
            }
            // Accumulate into a local array to avoid triggering recomputeDerivedNotes per batch
            var accumulated: [Note] = []
            while true {
                var descriptor = FetchDescriptor<NoteEntity>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                )
                descriptor.fetchOffset = currentOffset
                descriptor.fetchLimit = self.batchSize

                let noteEntities = try modelContext.fetch(descriptor)
                let newNotes = noteEntities.map { $0.toNote() }

                guard !newNotes.isEmpty else { break }
                accumulated.append(contentsOf: newNotes)
                logger.info("Loaded \(newNotes.count) additional notes (offset: \(currentOffset))")

                if newNotes.count < self.batchSize { break }
                currentOffset += newNotes.count
            }
            if !accumulated.isEmpty {
                notes.append(contentsOf: accumulated)
            }
        } catch {
            logger.error("Failed to load more notes: \(error)")
        }
    }

    func clearMemoryCache() {
        // Reset to initial load limit
        loadNotes()
        loadFolders()
    }
}
