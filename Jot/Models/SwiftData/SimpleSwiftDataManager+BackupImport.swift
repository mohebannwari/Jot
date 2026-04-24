import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    func allNotesForBackup() throws -> [Note] {
        let descriptor = FetchDescriptor<NoteEntity>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toNote() }
    }

    func allFoldersForBackup() throws -> [Folder] {
        let descriptor = FetchDescriptor<FolderEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toFolder() }
    }

    func allSmartFoldersForBackup() throws -> [SmartFolder] {
        let descriptor = FetchDescriptor<SmartFolderEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toSmartFolder() }
    }

    // MARK: - Backup Import

    /// Replaces all notes and folders with data from a backup.
    func importBackup(notes: [Note], folders: [Folder], smartFolders: [SmartFolder] = []) {
        do {
            // Clear all existing notes
            let noteDescriptor = FetchDescriptor<NoteEntity>()
            for entity in try modelContext.fetch(noteDescriptor) {
                modelContext.delete(entity)
            }

            // Clear all existing folders
            let folderDescriptor = FetchDescriptor<FolderEntity>()
            for entity in try modelContext.fetch(folderDescriptor) {
                modelContext.delete(entity)
            }

            let smartFolderDescriptor = FetchDescriptor<SmartFolderEntity>()
            for entity in try modelContext.fetch(smartFolderDescriptor) {
                modelContext.delete(entity)
            }

            // Clear all version snapshots (they reference the old notes)
            let versionDescriptor = FetchDescriptor<NoteVersionEntity>()
            for entity in try modelContext.fetch(versionDescriptor) {
                modelContext.delete(entity)
            }

            // Insert notes from backup
            for note in notes {
                let entity = NoteEntity(from: note)
                modelContext.insert(entity)
            }

            // Insert folders from backup
            for folder in folders {
                let entity = FolderEntity(from: folder)
                modelContext.insert(entity)
            }

            for smartFolder in smartFolders {
                let entity = SmartFolderEntity(from: smartFolder)
                modelContext.insert(entity)
            }

            try modelContext.save()

            // Reload in-memory state — single-pass partition for efficiency
            var activeNotes: [Note] = []
            var archived: [Note] = []
            var deleted: [Note] = []
            for note in notes {
                if note.isDeleted { deleted.append(note) }
                else if note.isArchived { archived.append(note) }
                else { activeNotes.append(note) }
            }
            var activeFolders: [Folder] = []
            var archivedFoldersList: [Folder] = []
            for folder in folders {
                if folder.isArchived { archivedFoldersList.append(folder) }
                else { activeFolders.append(folder) }
            }
            // Smart folders must be set before `notes` so `recomputeDerivedNotes` sees imported predicates.
            self.smartFolders = smartFolders
            self.folders = activeFolders
            self.archivedFolders = archivedFoldersList
            self.notes = activeNotes.sorted { $0.date > $1.date }
            self.archivedNotes = archived
            self.deletedNotes = deleted

            // Re-index in Spotlight
            for note in self.notes {
                SpotlightIndexer.shared.indexNote(note)
            }

            logger.info("Imported backup: \(notes.count) notes, \(folders.count) folders, \(smartFolders.count) smart folders")
        } catch {
            logger.error("Failed to import backup: \(error)")
        }
    }

}
