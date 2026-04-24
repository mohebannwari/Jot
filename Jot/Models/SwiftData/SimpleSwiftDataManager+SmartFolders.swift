import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    func loadSmartFolders() {
        do {
            let descriptor = FetchDescriptor<SmartFolderEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let entities = try modelContext.fetch(descriptor)
            smartFolders = entities.map { $0.toSmartFolder() }
        } catch {
            logger.error("Failed to load smart folders: \(error)")
            smartFolders = []
        }
        recomputeSmartFolderMembership(sortedNotes: notes.sorted(by: sidebarSortComparator()))
    }
    
    // MARK: - Smart Folder Operations

    @discardableResult
    func createSmartFolder(name: String, predicate: SmartFolderPredicate) -> SmartFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, predicate.hasAnyActiveCriterion else { return nil }

        let entity = SmartFolderEntity(name: trimmed, predicate: predicate)
        modelContext.insert(entity)

        do {
            try modelContext.save()
            let folder = entity.toSmartFolder()
            smartFolders.insert(folder, at: 0)
            recomputeSmartFolderMembership(sortedNotes: notes.sorted(by: sidebarSortComparator()))
            return folder
        } catch {
            logger.error("Failed to create smart folder: \(error)")
            return nil
        }
    }

    func updateSmartFolder(id: UUID, name: String, predicate: SmartFolderPredicate) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, predicate.hasAnyActiveCriterion else { return }

        do {
            let pid = id
            let p = #Predicate<SmartFolderEntity> { $0.id == pid }
            let descriptor = FetchDescriptor(predicate: p)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Smart folder \(id) not found for update")
                return
            }

            entity.update(name: trimmed, predicate: predicate)
            try modelContext.save()

            if let index = smartFolders.firstIndex(where: { $0.id == id }) {
                smartFolders[index] = entity.toSmartFolder()
            }
            recomputeSmartFolderMembership(sortedNotes: notes.sorted(by: sidebarSortComparator()))
        } catch {
            logger.error("Failed to update smart folder: \(error)")
        }
    }

    func deleteSmartFolder(id: UUID) {
        do {
            let pid = id
            let p = #Predicate<SmartFolderEntity> { $0.id == pid }
            let descriptor = FetchDescriptor(predicate: p)
            let entities = try modelContext.fetch(descriptor)
            guard let entity = entities.first else {
                logger.warning("Smart folder \(id) not found for deletion")
                return
            }

            modelContext.delete(entity)
            try modelContext.save()

            smartFolders.removeAll { $0.id == id }
            notesBySmartFolderID[id] = nil
        } catch {
            logger.error("Failed to delete smart folder: \(error)")
        }
    }
}
