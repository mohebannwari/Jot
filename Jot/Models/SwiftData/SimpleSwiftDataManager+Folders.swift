import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    func loadFolders() {
        do {
            let predicate = #Predicate<FolderEntity> { $0.isArchived == false }
            let descriptor = FetchDescriptor<FolderEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let folderEntities = try modelContext.fetch(descriptor)
            folders = folderEntities.map { $0.toFolder() }
        } catch {
            logger.error("Failed to load folders: \(error)")
            folders = []
        }
        loadSmartFolders()
    }

    func loadArchivedFolders() {
        do {
            let predicate = #Predicate<FolderEntity> { $0.isArchived == true }
            let descriptor = FetchDescriptor<FolderEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let folderEntities = try modelContext.fetch(descriptor)
            archivedFolders = folderEntities.map { $0.toFolder() }
            logger.info("Loaded \(folderEntities.count) archived folders")
        } catch {
            logger.error("Failed to load archived folders: \(error)")
            archivedFolders = []
        }
    }

    func archiveFolder(_ folder: Folder) {
        do {
            let predicate = #Predicate<FolderEntity> { $0.id == folder.id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Folder with ID \(folder.id) not found for archiving")
                return
            }
            
            entity.isArchived = true
            entity.modifiedAt = Date()
            try modelContext.save()
            
            folders.removeAll { $0.id == folder.id }
            loadArchivedFolders()
            
            logger.info("Archived folder: \(folder.name)")
        } catch {
            logger.error("Failed to archive folder: \(error)")
        }
    }
    
    func unarchiveFolder(_ folder: Folder) {
        do {
            let predicate = #Predicate<FolderEntity> { $0.id == folder.id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Folder with ID \(folder.id) not found for unarchiving")
                return
            }
            
            entity.isArchived = false
            entity.modifiedAt = Date()
            try modelContext.save()
            
            archivedFolders.removeAll { $0.id == folder.id }
            loadFolders()
            
            logger.info("Unarchived folder: \(folder.name)")
        } catch {
            logger.error("Failed to unarchive folder: \(error)")
        }
    }

    // MARK: - Folder Operations

    @discardableResult
    func createFolder(name: String, colorHex: String? = nil) -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entity = FolderEntity(name: trimmed, colorHex: colorHex)
        modelContext.insert(entity)

        do {
            try modelContext.save()
            let folder = entity.toFolder()
            folders.insert(folder, at: 0)
            return folder
        } catch {
            logger.error("Failed to create folder: \(error)")
            return nil
        }
    }

    /// Restores a previously deleted folder, preserving its original UUID and metadata.
    /// Used by the undo system to faithfully reverse a folder deletion.
    @discardableResult
    func restoreFolder(_ folder: Folder) -> Folder? {
        let entity = FolderEntity(from: folder)
        modelContext.insert(entity)

        do {
            try modelContext.save()
            let restored = entity.toFolder()
            folders.insert(restored, at: 0)
            return restored
        } catch {
            logger.error("Failed to restore folder: \(error)")
            return nil
        }
    }

    func renameFolder(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let predicate = #Predicate<FolderEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Folder with ID \(id) not found for rename")
                return
            }

            entity.rename(to: trimmed)
            try modelContext.save()

            if let index = folders.firstIndex(where: { $0.id == id }) {
                folders[index].name = trimmed
                folders[index].modifiedAt = entity.modifiedAt
            }
        } catch {
            logger.error("Failed to rename folder: \(error)")
        }
    }

    func updateFolder(id: UUID, name: String, colorHex: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let predicate = #Predicate<FolderEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Folder with ID \(id) not found for update")
                return
            }

            entity.update(name: trimmed, colorHex: colorHex)
            try modelContext.save()

            if let index = folders.firstIndex(where: { $0.id == id }) {
                folders[index].name = trimmed
                folders[index].colorHex = colorHex
                folders[index].modifiedAt = entity.modifiedAt
            }
        } catch {
            logger.error("Failed to update folder: \(error)")
        }
    }

    func deleteFolder(id: UUID) {
        do {
            let folderPredicate = #Predicate<FolderEntity> { $0.id == id }
            let folderDescriptor = FetchDescriptor(predicate: folderPredicate)
            let folderEntities = try modelContext.fetch(folderDescriptor)
            guard let folderEntity = folderEntities.first else {
                logger.warning("Folder with ID \(id) not found for deletion")
                return
            }

            let notePredicate = #Predicate<NoteEntity> { $0.folderID == id }
            let noteDescriptor = FetchDescriptor(predicate: notePredicate)
            let noteEntities = try modelContext.fetch(noteDescriptor)

            for noteEntity in noteEntities {
                noteEntity.folderID = nil
            }

            modelContext.delete(folderEntity)
            try modelContext.save()

            folders.removeAll { $0.id == id }
            archivedFolders.removeAll { $0.id == id }
            for index in notes.indices where notes[index].folderID == id {
                notes[index].folderID = nil
            }
        } catch {
            logger.error("Failed to delete folder: \(error)")
        }
    }

    @discardableResult
    func createFolder(withNoteID noteID: UUID, name: String) -> Folder? {
        guard let folder = createFolder(name: name) else {
            return nil
        }

        _ = moveNote(id: noteID, toFolderID: folder.id)
        return folder
    }

    @discardableResult
    func moveNote(id: UUID, toFolderID folderID: UUID?) -> Bool {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for move")
                return false
            }

            noteEntity.folderID = folderID
            if folderID != nil {
                noteEntity.isPinned = false
            }

            try modelContext.save()

            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].folderID = folderID
                if folderID != nil {
                    notes[index].isPinned = false
                }
            }

            return true
        } catch {
            logger.error("Failed to move note: \(error)")
            return false
        }
    }

    @discardableResult
    func moveNotes(ids: Set<UUID>, toFolderID folderID: UUID?) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let idArray = Array(ids)
            let predicate = #Predicate<NoteEntity> { idArray.contains($0.id) }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let toMove = try modelContext.fetch(descriptor)

            guard !toMove.isEmpty else {
                logger.warning("No matching notes found for batch move")
                return 0
            }

            for entity in toMove {
                entity.folderID = folderID
                if folderID != nil {
                    entity.isPinned = false
                }
            }

            try modelContext.save()

            for index in notes.indices where ids.contains(notes[index].id) {
                notes[index].folderID = folderID
                if folderID != nil {
                    notes[index].isPinned = false
                }
            }

            logger.info("Moved \(toMove.count) notes in batch")
            return toMove.count
        } catch {
            logger.error("Failed to batch move notes: \(error)")
            return 0
        }
    }

}
