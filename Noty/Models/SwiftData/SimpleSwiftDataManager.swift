import Foundation
import SwiftData
import Combine
import OSLog

/// Simple SwiftData manager for testing and incremental implementation
@MainActor
final class SimpleSwiftDataManager: ObservableObject {

    @Published var notes: [Note] = []
    @Published var archivedNotes: [Note] = []
    @Published var folders: [Folder] = []
    @Published private(set) var hasLoadedInitialNotes = false
    @Published private(set) var hasCompletedMigrationCheck = false

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let backgroundContext: ModelContext
    private let shouldAutoMigrateFromJSON: Bool
    private let logger = Logger(subsystem: "com.noty.app", category: "SimpleSwiftDataManager")
    private let performanceMonitor = PerformanceMonitor.shared

    // MARK: - Performance Configuration
    private let batchSize = 50
    private let maxLoadLimit = 500

    init(autoMigrateFromJSON: Bool = true) throws {
        // Setup SwiftData container
        let schema = Schema([NoteEntity.self, TagEntity.self, FolderEntity.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)
        self.backgroundContext = ModelContext(modelContainer)
        self.shouldAutoMigrateFromJSON = autoMigrateFromJSON

        // Configure main context for UI
        modelContext.autosaveEnabled = true

        // Configure background context for performance
        backgroundContext.autosaveEnabled = false

        // Load initial data with deterministic readiness sequencing
        hasLoadedInitialNotes = false
        hasCompletedMigrationCheck = false
        loadFolders()

        // Auto-migrate from JSON if enabled, then load notes for initial UI state
        Task {
            if self.shouldAutoMigrateFromJSON {
                await self.autoMigrateFromJSONIfNeeded()
            } else {
                self.hasCompletedMigrationCheck = true
            }

            self.loadNotes(isInitialLoad: true)
        }
    }

    // MARK: - Basic Operations

    private func fetchNotesFromStore(limit: Int? = nil) throws -> [Note] {
        let predicate = #Predicate<NoteEntity> { $0.isArchived == false }
        var descriptor = FetchDescriptor<NoteEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor).map { $0.toNote() }
    }

    private func loadNotes(isInitialLoad: Bool = false) {
        Task {
            defer {
                if isInitialLoad {
                    self.hasLoadedInitialNotes = true
                }
            }
            do {
                self.notes = try await performanceMonitor.trackSwiftDataOperation(
                    operation: .fetch,
                    recordCount: 0
                ) {
                    let predicate = #Predicate<NoteEntity> { $0.isArchived == false }
                    var descriptor = FetchDescriptor<NoteEntity>(
                        predicate: predicate,
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    descriptor.fetchLimit = self.maxLoadLimit
                    let notes = try modelContext.fetch(descriptor).map { $0.toNote() }

                    await MainActor.run {
                        logger.info("Loaded \(notes.count) notes from SwiftData (limited to \(self.maxLoadLimit))")
                    }

                    return notes
                }
            } catch {
                await MainActor.run {
                    logger.error("Failed to load notes: \(error)")
                    self.notes = []
                }
            }
        }
    }

    func loadArchivedNotes() {
        do {
            let predicate = #Predicate<NoteEntity> { $0.isArchived == true }
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

    private func loadFolders() {
        do {
            let descriptor = FetchDescriptor<FolderEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let folderEntities = try modelContext.fetch(descriptor)
            folders = folderEntities.map { $0.toFolder() }
        } catch {
            logger.error("Failed to load folders: \(error)")
            folders = []
        }
    }

    func addNote(
        title: String = "Untitled",
        content: String = "",
        tags: [String] = [],
        folderID: UUID? = nil
    ) -> Note {
        let noteEntity = NoteEntity(title: title, content: content)
        noteEntity.folderID = folderID
        if folderID != nil {
            noteEntity.isPinned = false
        }
        noteEntity.setTags(tags, in: modelContext)

        modelContext.insert(noteEntity)

        do {
            try modelContext.save()
            let note = noteEntity.toNote()
            notes.insert(note, at: 0)
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

            noteEntity.updateTitle(updatedNote.title)
            noteEntity.updateContent(updatedNote.content)
            noteEntity.folderID = updatedNote.folderID
            noteEntity.isPinned = updatedNote.folderID == nil ? updatedNote.isPinned : false
            noteEntity.setTags(updatedNote.tags, in: modelContext)

            try modelContext.save()

            // Update local array
            if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                var localNote = updatedNote
                if localNote.folderID != nil {
                    localNote.isPinned = false
                }
                notes[index] = localNote
            }

            logger.info("Updated note: \(updatedNote.title)")

        } catch {
            logger.error("Failed to update note: \(error)")
        }
    }

    func deleteNote(id: UUID) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for deletion")
                return
            }

            modelContext.delete(noteEntity)
            try modelContext.save()

            notes.removeAll { $0.id == id }
            logger.info("Deleted note with ID: \(id)")

        } catch {
            logger.error("Failed to delete note: \(error)")
        }
    }

    @discardableResult
    func deleteNotes(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let descriptor = FetchDescriptor<NoteEntity>()
            let entities = try modelContext.fetch(descriptor)
            let toDelete = entities.filter { ids.contains($0.id) }

            guard !toDelete.isEmpty else {
                logger.warning("No matching notes found for batch delete")
                return 0
            }

            for entity in toDelete {
                modelContext.delete(entity)
            }

            try modelContext.save()
            notes.removeAll { ids.contains($0.id) }
            logger.info("Deleted \(toDelete.count) notes in batch")
            return toDelete.count
        } catch {
            logger.error("Failed to batch delete notes: \(error)")
            return 0
        }
    }

    // MARK: - Archive Operations

    @discardableResult
    func archiveNotes(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        do {
            let descriptor = FetchDescriptor<NoteEntity>()
            let entities = try modelContext.fetch(descriptor)
            let toArchive = entities.filter { ids.contains($0.id) && !$0.isArchived }

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
            let predicate = #Predicate<NoteEntity> { $0.isArchived == true }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            let toUnarchive = entities.filter { ids.contains($0.id) }

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
            logger.info("Unarchived \(toUnarchive.count) notes in batch")
            return toUnarchive.count
        } catch {
            logger.error("Failed to batch unarchive notes: \(error)")
            return 0
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
                noteEntity.setTags(note.tags, in: modelContext)
                modelContext.insert(noteEntity)
            }

            try modelContext.save()
            notes = newNotes
            logger.info("Replaced all notes with \(newNotes.count) new notes")

        } catch {
            logger.error("Failed to replace all notes: \(error)")
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
            let descriptor = FetchDescriptor<NoteEntity>()
            let entities = try modelContext.fetch(descriptor)
            let toMove = entities.filter { ids.contains($0.id) }

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

    // MARK: - Search

    func searchNotes(query: String, limit: Int = 100) async -> [Note] {
        performanceMonitor.trackFeatureUsage("search")

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return notes
        }

        let sanitizedTagQuery = normalizedQuery.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = sanitizedTagQuery != normalizedQuery && !sanitizedTagQuery.isEmpty

        do {
            return try await performanceMonitor.trackSwiftDataOperation(
                operation: .search,
                recordCount: 0
            ) {
                let predicate = NoteEntity.searchPredicate(for: normalizedQuery)
                let sortDescriptors = NoteEntity.sortByRelevance(query: normalizedQuery)
                var descriptor = FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

                // Limit search results for better performance
                descriptor.fetchLimit = limit

                let entities = try modelContext.fetch(descriptor)
                let results = entities.map { $0.toNote() }

                await MainActor.run {
                    logger.info("Search for '\(query)' returned \(results.count) results")
                }

                return results
            }
        } catch {
            logger.error("Search failed: \(error)")
            // Fallback to in-memory search with limit
            let filtered = notes.filter { note in
                let titleMatches = note.title.localizedCaseInsensitiveContains(normalizedQuery) ||
                    (hasDistinctTagQuery && note.title.localizedCaseInsensitiveContains(sanitizedTagQuery))
                let contentMatches = note.content.localizedCaseInsensitiveContains(normalizedQuery) ||
                    (hasDistinctTagQuery && note.content.localizedCaseInsensitiveContains(sanitizedTagQuery))
                let tagMatchesPrimary = note.tags.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
                let tagMatchesFallback = hasDistinctTagQuery &&
                    note.tags.contains { $0.localizedCaseInsensitiveContains(sanitizedTagQuery) }

                return titleMatches || contentMatches || tagMatchesPrimary || tagMatchesFallback
            }
            return Array(filtered.prefix(limit))
        }
    }

    // MARK: - Migration Helper

    private func autoMigrateFromJSONIfNeeded() async {
        defer {
            hasCompletedMigrationCheck = true
        }

        // Check if SwiftData is empty
        do {
            let descriptor = FetchDescriptor<NoteEntity>()
            let existingNotes = try modelContext.fetch(descriptor)

            // If SwiftData already has notes, skip migration
            guard existingNotes.isEmpty else {
                logger.info("SwiftData already has notes, skipping migration")
                return
            }

            // Check if JSON file exists
            let jsonURL = NotesManager.getStorageURL()
            guard FileManager.default.fileExists(atPath: jsonURL.path) else {
                logger.info("No JSON file found, starting with empty database")
                return
            }

            // Load JSON notes
            let data = try Data(contentsOf: jsonURL)
            let jsonNotes = try JSONDecoder().decode([Note].self, from: data)

            guard !jsonNotes.isEmpty else {
                logger.info("JSON file is empty, nothing to migrate")
                return
            }

            logger.info("Found \(jsonNotes.count) notes in JSON, starting migration...")
            hasLoadedInitialNotes = false

            // Perform migration
            try await migrateFromJSON(jsonNotes)

            logger.info("Migration completed successfully")

        } catch {
            logger.error("Auto-migration failed: \(error)")
        }
    }

    private func backupJSONFile() {
        let jsonURL = NotesManager.getStorageURL()
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            logger.info("No JSON file to backup")
            return
        }

        let backupURL = jsonURL.deletingLastPathComponent()
            .appendingPathComponent("notes.json.backup.\(Date().timeIntervalSince1970)")

        do {
            try FileManager.default.copyItem(at: jsonURL, to: backupURL)
            logger.info("Created backup at: \(backupURL.path)")
        } catch {
            logger.error("Failed to create backup: \(error)")
        }
    }

    func migrateFromJSON(_ jsonNotes: [Note]) async throws {
        logger.info("Starting migration of \(jsonNotes.count) notes from JSON")

        // Create backup before migration
        backupJSONFile()

        // Use background context for large operations
        await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    // Process in batches to manage memory
                    for batch in jsonNotes.chunked(into: self.batchSize) {
                        try await self.migrateBatch(batch)

                        // Yield control periodically to prevent blocking
                        await Task.yield()
                    }

                    await MainActor.run {
                        do {
                            self.notes = try self.fetchNotesFromStore(limit: self.maxLoadLimit)
                            self.logger.info("Migration completed successfully")
                        } catch {
                            self.notes = []
                            self.logger.error("Migration reload failed: \(error)")
                        }
                        self.hasLoadedInitialNotes = true
                        continuation.resume()
                    }
                } catch {
                    await MainActor.run {
                        self.logger.error("Migration failed: \(error)")
                        self.hasLoadedInitialNotes = true
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func migrateBatch(_ notes: [Note]) async throws {
        // Create a new background context for this batch
        let batchContext = ModelContext(modelContainer)
        batchContext.autosaveEnabled = false

        for note in notes {
            let noteEntity = NoteEntity(from: note)
            noteEntity.setTags(note.tags, in: batchContext)
            batchContext.insert(noteEntity)
        }

        // Save batch and clean up
        try batchContext.save()

        logger.info("Migrated batch of \(notes.count) notes")
    }

    // MARK: - Testing Helpers

    func clearAllData() throws {
        let noteDescriptor = FetchDescriptor<NoteEntity>()
        let noteEntities = try modelContext.fetch(noteDescriptor)
        for note in noteEntities {
            modelContext.delete(note)
        }

        let tagDescriptor = FetchDescriptor<TagEntity>()
        let tagEntities = try modelContext.fetch(tagDescriptor)
        for tag in tagEntities {
            modelContext.delete(tag)
        }

        let folderDescriptor = FetchDescriptor<FolderEntity>()
        let folderEntities = try modelContext.fetch(folderDescriptor)
        for folder in folderEntities {
            modelContext.delete(folder)
        }

        try modelContext.save()
        notes.removeAll()
        folders.removeAll()

        logger.info("Cleared all SwiftData")
    }

    // MARK: - Memory Management

    func loadMoreNotes(offset: Int = 0) {
        do {
            var descriptor = FetchDescriptor<NoteEntity>(
                sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = self.batchSize

            let noteEntities = try modelContext.fetch(descriptor)
            let newNotes = noteEntities.map { $0.toNote() }

            // Append to existing notes
            notes.append(contentsOf: newNotes)
            logger.info("Loaded \(newNotes.count) additional notes (offset: \(offset))")
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

// MARK: - Array Extension for Batch Processing

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
