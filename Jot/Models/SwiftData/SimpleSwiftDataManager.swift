import Foundation
import SwiftData
import Combine
import OSLog

/// Simple SwiftData manager for testing and incremental implementation
@MainActor
final class SimpleSwiftDataManager: ObservableObject {

    @Published var notes: [Note] = [] {
        didSet { recomputeDerivedNotes() }
    }
    @Published var archivedNotes: [Note] = []
    @Published var deletedNotes: [Note] = []
    @Published var folders: [Folder] = []
    @Published var archivedFolders: [Folder] = []

    // Sidebar groupings — recomputed only when notes change, not on every UI state change
    @Published private(set) var notesByFolderID: [UUID: [Note]] = [:]
    @Published private(set) var unfiledNotes: [Note] = []
    @Published private(set) var pinnedNotes: [Note] = []
    @Published private(set) var todayNotes: [Note] = []
    @Published private(set) var thisMonthNotes: [Note] = []
    @Published private(set) var thisYearNotes: [Note] = []
    @Published private(set) var olderNotes: [Note] = []
    @Published private(set) var allUnpinnedNotes: [Note] = []
    @Published private(set) var hasLoadedInitialNotes = false
    @Published private(set) var hasCompletedMigrationCheck = false

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let backgroundContext: ModelContext
    private let logger = Logger(subsystem: "com.jot.app", category: "SimpleSwiftDataManager")

    // MARK: - Performance Configuration
    private let batchSize = 50
    private let maxLoadLimit = 500

    init() throws {
        // Setup SwiftData container
        let schema = Schema([NoteEntity.self, FolderEntity.self])
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

        // Cleanup any leftover performance test notes
        cleanupPerformanceNotes()

        // Load initial data
        hasLoadedInitialNotes = false
        hasCompletedMigrationCheck = true
        loadFolders()

        Task {
            self.loadNotes(isInitialLoad: true)
        }
    }

    private func cleanupPerformanceNotes() {
        do {
            let descriptor = FetchDescriptor<NoteEntity>(
                predicate: #Predicate<NoteEntity> { $0.title.contains("Performance Note") }
            )
            let entities = try modelContext.fetch(descriptor)
            
            guard !entities.isEmpty else { return }
            
            logger.info("Found \(entities.count) performance notes to cleanup")
            for entity in entities {
                modelContext.delete(entity)
            }
            try modelContext.save()
            logger.info("Successfully removed performance notes")
        } catch {
            logger.error("Failed to cleanup performance notes: \(error)")
        }
    }

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

    private func loadNotes(isInitialLoad: Bool = false) {
        Task {
            defer {
                if isInitialLoad {
                    self.hasLoadedInitialNotes = true
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

    // Recomputes all derived note collections in a single pass over notes.
    // Called only when notes array changes — not on every UI render.
    private func recomputeDerivedNotes() {
        let sortOrderRaw = UserDefaults.standard.string(forKey: ThemeManager.noteSortOrderKey) ?? "dateEdited"
        let sortOrder = NoteSortOrder(rawValue: sortOrderRaw) ?? .dateEdited

        let sortComparator: (Note, Note) -> Bool = {
            switch sortOrder {
            case .dateEdited: return { $0.date > $1.date }
            case .dateCreated: return { $0.createdAt > $1.createdAt }
            case .title: return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        }()

        let groupDate: (Note) -> Date = sortOrder == .dateCreated ? { $0.createdAt } : { $0.date }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        notesByFolderID = Dictionary(
            grouping: notes.filter { $0.folderID != nil },
            by: { $0.folderID! }
        ).mapValues { $0.sorted(by: sortComparator) }

        let unfiled = notes.filter { $0.folderID == nil }
        unfiledNotes = unfiled
        pinnedNotes = unfiled.filter { $0.isPinned }.sorted(by: sortComparator)

        let unpinned = unfiled.filter { !$0.isPinned }
        allUnpinnedNotes = unpinned.sorted(by: sortComparator)

        todayNotes = unpinned.filter { calendar.isDate(groupDate($0), inSameDayAs: now) }.sorted(by: sortComparator)
        thisMonthNotes = unpinned.filter { note in
            let d = groupDate(note)
            let noteDay = calendar.startOfDay(for: d)
            let noteMonth = calendar.component(.month, from: d)
            let noteYear = calendar.component(.year, from: d)
            return noteMonth == currentMonth && noteYear == currentYear && noteDay < todayStart
        }.sorted(by: sortComparator)
        thisYearNotes = unpinned.filter { note in
            let d = groupDate(note)
            let noteMonth = calendar.component(.month, from: d)
            let noteYear = calendar.component(.year, from: d)
            return noteYear == currentYear && noteMonth < currentMonth
        }.sorted(by: sortComparator)
        olderNotes = unpinned.filter { note in
            calendar.component(.year, from: groupDate(note)) < currentYear
        }.sorted(by: sortComparator)
    }

    /// Re-sorts derived note collections when user changes sort preference.
    func refreshSorting() {
        recomputeDerivedNotes()
    }

    private func loadFolders() {
        do {
            let predicate = #Predicate<FolderEntity> { $0.isArchived == false }
            var descriptor = FetchDescriptor<FolderEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let folderEntities = try modelContext.fetch(descriptor)
            folders = folderEntities.map { $0.toFolder() }
        } catch {
            logger.error("Failed to load folders: \(error)")
            folders = []
        }
    }
    
    func loadArchivedFolders() {
        do {
            let predicate = #Predicate<FolderEntity> { $0.isArchived == true }
            var descriptor = FetchDescriptor<FolderEntity>(
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
            noteEntity.isLocked = updatedNote.isLocked


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
        moveToTrash(ids: [id])
    }

    @discardableResult
    func deleteNotes(ids: Set<UUID>) -> Int {
        moveToTrash(ids: ids)
    }

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
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            let toRestore = entities.filter { ids.contains($0.id) }

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
            let predicate = #Predicate<NoteEntity> { $0.isDeleted == true }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            let entities = try modelContext.fetch(descriptor)
            let toDelete = entities.filter { ids.contains($0.id) }

            guard !toDelete.isEmpty else {
                logger.warning("No matching deleted notes found for permanent delete")
                return 0
            }

            for entity in toDelete {
                modelContext.delete(entity)
            }

            try modelContext.save()
            deletedNotes.removeAll { ids.contains($0.id) }
            logger.info("Permanently deleted \(toDelete.count) notes")
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

            for entity in entities {
                modelContext.delete(entity)
            }

            try modelContext.save()
            deletedNotes.removeAll()
            logger.info("Emptied trash (\(entities.count) notes)")
        } catch {
            logger.error("Failed to empty trash: \(error)")
        }
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

            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isLocked.toggle()
            }

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

    // MARK: - Search

    func searchNotes(query: String, limit: Int = 100) async -> [Note] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return notes
        }

        let sanitizedTagQuery = normalizedQuery.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = sanitizedTagQuery != normalizedQuery && !sanitizedTagQuery.isEmpty

        do {
            let predicate = NoteEntity.searchPredicate(for: normalizedQuery)
            let sortDescriptors = NoteEntity.sortByRelevance(query: normalizedQuery)
            var descriptor = FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
            descriptor.fetchLimit = limit

            let entities = try modelContext.fetch(descriptor)
            let results = entities.map { $0.toNote() }
            logger.info("Search for '\(query)' returned \(results.count) results")
            return results
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
