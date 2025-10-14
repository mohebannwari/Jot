import Foundation
import SwiftData
import Combine
import OSLog

/// Simple SwiftData manager for testing and incremental implementation
@MainActor
final class SimpleSwiftDataManager: ObservableObject {

    @Published var notes: [Note] = []

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let backgroundContext: ModelContext
    private let logger = Logger(subsystem: "com.noty.app", category: "SimpleSwiftDataManager")
    private let performanceMonitor = PerformanceMonitor.shared

    // MARK: - Performance Configuration
    private let batchSize = 50
    private let maxLoadLimit = 500

    init() throws {
        // Setup SwiftData container
        let schema = Schema([NoteEntity.self, TagEntity.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)
        self.backgroundContext = ModelContext(modelContainer)

        // Configure main context for UI
        modelContext.autosaveEnabled = true

        // Configure background context for performance
        backgroundContext.autosaveEnabled = false

        // Load initial data with limit
        loadNotes()

        // Auto-migrate from JSON if exists and SwiftData is empty
        Task {
            await autoMigrateFromJSONIfNeeded()
        }
    }

    // MARK: - Basic Operations

    private func loadNotes() {
        Task {
            do {
                self.notes = try await performanceMonitor.trackSwiftDataOperation(
                    operation: .fetch,
                    recordCount: 0
                ) {
                    var descriptor = FetchDescriptor<NoteEntity>(
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    // Limit initial load for better performance
                    descriptor.fetchLimit = self.maxLoadLimit

                    let noteEntities = try modelContext.fetch(descriptor)
                    let notes = noteEntities.map { $0.toNote() }

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

    func addNote(title: String = "Untitled", content: String = "", tags: [String] = []) -> Note {
        let noteEntity = NoteEntity(title: title, content: content)
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
            return Note(title: title, content: content, tags: tags)
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
            noteEntity.setTags(updatedNote.tags, in: modelContext)

            try modelContext.save()

            // Update local array
            if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                notes[index] = updatedNote
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

    func togglePin(id: UUID) {
        do {
            let predicate = #Predicate<NoteEntity> { $0.id == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)

            guard let noteEntity = entities.first else {
                logger.warning("Note with ID \(id) not found for toggle pin")
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
                        // Reload UI on main thread
                        self.loadNotes()
                        self.logger.info("Migration completed successfully")
                        continuation.resume()
                    }
                } catch {
                    await MainActor.run {
                        self.logger.error("Migration failed: \(error)")
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

        try modelContext.save()
        notes.removeAll()

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
