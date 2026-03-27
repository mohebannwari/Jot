import Foundation
import SwiftData
import Combine
import OSLog

/// Simple SwiftData manager for testing and incremental implementation
@MainActor
final class SimpleSwiftDataManager: ObservableObject {

    /// Singleton set during JotApp.init() so App Intents can access the data layer in-process.
    static var shared: SimpleSwiftDataManager?

    @Published var notes: [Note] = [] {
        didSet {
            guard !suppressDerivedRecompute else { return }
            recomputeDerivedNotes()
        }
    }
    /// When true, `notes` didSet skips recomputeDerivedNotes().
    /// Used for content-only saves where sidebar groupings don't change.
    private var suppressDerivedRecompute = false
    @Published var archivedNotes: [Note] = []
    @Published var deletedNotes: [Note] = []
    @Published var folders: [Folder] = []
    @Published var archivedFolders: [Folder] = []

    // Sidebar groupings — recomputed only when notes change, not on every UI state change.
    // NOT @Published — objectWillChange is sent once manually in recomputeDerivedNotes()
    // to avoid 9 separate SwiftUI invalidation passes per note save.
    private(set) var notesByFolderID: [UUID: [Note]] = [:]
    private(set) var unfiledNotes: [Note] = []
    private(set) var pinnedNotes: [Note] = []
    private(set) var lockedNotes: [Note] = []
    private(set) var todayNotes: [Note] = []
    private(set) var thisMonthNotes: [Note] = []
    private(set) var thisYearNotes: [Note] = []
    private(set) var olderNotes: [Note] = []
    private(set) var allUnpinnedNotes: [Note] = []
    @Published private(set) var hasLoadedInitialNotes = false
    @Published private(set) var hasCompletedMigrationCheck = false

    private let modelContainer: ModelContainer
    private(set) var modelContext: ModelContext
    private let logger = Logger(subsystem: "com.jot.app", category: "SimpleSwiftDataManager")

    // MARK: - Performance Configuration
    private let batchSize = 50
    private let maxLoadLimit = 500

    init() throws {
        // Setup SwiftData container
        let schema = Schema([NoteEntity.self, FolderEntity.self, NoteVersionEntity.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)

        // Configure main context for UI
        modelContext.autosaveEnabled = true

        // Cleanup any leftover performance test notes
        cleanupPerformanceNotes()

        // Load initial data
        hasLoadedInitialNotes = false
        hasCompletedMigrationCheck = true
        loadFolders()

        Task { @MainActor in
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
        Task { @MainActor in
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

        // Sort once, then partition in a single forward pass.
        // Previous implementation sorted each sub-collection independently (9 O(n log n) passes).
        let sorted = notes.sorted(by: sortComparator)

        var folderDict: [UUID: [Note]] = [:]
        var unfiled: [Note] = []
        var pinned: [Note] = []
        var locked: [Note] = []
        var allUnpinned: [Note] = []
        var today: [Note] = []
        var month: [Note] = []
        var year: [Note] = []
        var older: [Note] = []

        for note in sorted {
            if let fid = note.folderID {
                folderDict[fid, default: []].append(note)
                continue
            }

            unfiled.append(note)

            if note.isPinned {
                pinned.append(note)
                continue
            }
            if note.isLocked {
                locked.append(note)
                continue
            }

            allUnpinned.append(note)

            let d = groupDate(note)
            if calendar.isDate(d, inSameDayAs: now) {
                today.append(note)
            } else {
                let noteYear = calendar.component(.year, from: d)
                if noteYear < currentYear {
                    older.append(note)
                } else {
                    let noteMonth = calendar.component(.month, from: d)
                    if noteMonth < currentMonth {
                        year.append(note)
                    } else {
                        let noteDay = calendar.startOfDay(for: d)
                        if noteDay < todayStart {
                            month.append(note)
                        }
                    }
                }
            }
        }

        notesByFolderID = folderDict
        unfiledNotes = unfiled
        pinnedNotes = pinned
        lockedNotes = locked
        allUnpinnedNotes = allUnpinned
        todayNotes = today
        thisMonthNotes = month
        thisYearNotes = year
        olderNotes = older
    }

    /// Updates a single note in-place across all derived sidebar collections
    /// without triggering a full recompute. Used after content-only saves.
    private func updateNoteInDerivedCollections(_ note: Note) {
        func patch(_ array: inout [Note]) {
            if let i = array.firstIndex(where: { $0.id == note.id }) {
                array[i] = note
            }
        }
        patch(&pinnedNotes)
        patch(&allUnpinnedNotes)
        patch(&unfiledNotes)
        patch(&lockedNotes)
        patch(&todayNotes)
        patch(&thisMonthNotes)
        patch(&thisYearNotes)
        patch(&olderNotes)
        for (key, var arr) in notesByFolderID {
            if let i = arr.firstIndex(where: { $0.id == note.id }) {
                arr[i] = note
                notesByFolderID[key] = arr
                break
            }
        }
    }

    /// Re-sorts derived note collections when user changes sort preference.
    func refreshSorting() {
        recomputeDerivedNotes()
    }

    private func loadFolders() {
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
            // Persist stickers
            if updatedNote.stickers.isEmpty {
                noteEntity.stickersData = nil
            } else {
                do {
                    noteEntity.stickersData = try JSONEncoder().encode(updatedNote.stickers)
                } catch {
                    logger.error("Failed to encode stickers: \(error)")
                }
            }
            // Preserve metadata from the authoritative local notes array — the editor's
            // noteForPersist may carry stale isPinned/isLocked/folderID values.
            noteEntity.folderID = existingNote?.folderID ?? updatedNote.folderID
            noteEntity.isPinned = existingNote?.isPinned ?? updatedNote.isPinned
            noteEntity.isLocked = existingNote?.isLocked ?? updatedNote.isLocked

            // Meeting notes
            noteEntity.isMeetingNote = updatedNote.isMeetingNote
            noteEntity.meetingTranscript = updatedNote.meetingTranscript
            noteEntity.meetingSummary = updatedNote.meetingSummary
            noteEntity.meetingDuration = updatedNote.meetingDuration
            noteEntity.meetingLanguage = updatedNote.meetingLanguage

            try modelContext.save()

            // Update local array — skip the expensive recomputeDerivedNotes() for content-only saves
            if let index = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                var localNote = updatedNote
                let existing = notes[index]
                localNote.isPinned = existing.isPinned
                localNote.isLocked = existing.isLocked
                localNote.folderID = existing.folderID
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

    /// Silently remove a note without moving it to trash (e.g. discarding an empty untitled note).
    func discardNote(id: UUID) {
        do {
            let targetID = id
            let predicate = #Predicate<NoteEntity> { $0.id == targetID }
            let descriptor = FetchDescriptor<NoteEntity>(predicate: predicate)
            if let entity = try modelContext.fetch(descriptor).first {
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
            SpotlightIndexer.shared.deindexNotes(ids: ids)
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

    // MARK: - Search

    func searchNotes(query: String, limit: Int = 100) async -> [Note] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return notes.filter { !$0.isLocked }
        }

        let sanitizedTagQuery = normalizedQuery.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = sanitizedTagQuery != normalizedQuery && !sanitizedTagQuery.isEmpty

        do {
            let predicate = NoteEntity.searchPredicate(for: normalizedQuery)
            let sortDescriptors = NoteEntity.sortByRelevance(query: normalizedQuery)
            var descriptor = FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
            descriptor.fetchLimit = limit

            let entities = try modelContext.fetch(descriptor)
            let results = entities.map { $0.toNote() }.filter { !$0.isLocked }
            logger.info("Search for '\(query)' returned \(results.count) results")
            return results
        } catch {
            logger.error("Search failed: \(error)")
            // Fallback to in-memory search with limit
            let filtered = notes.filter { !$0.isLocked }.filter { note in
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


    // MARK: - Backup Import

    /// Replaces all notes and folders with data from a backup.
    func importBackup(notes: [Note], folders: [Folder]) {
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

            try modelContext.save()

            // Reload in-memory state
            self.notes = notes.filter { !$0.isArchived && !$0.isDeleted }
            self.archivedNotes = notes.filter { $0.isArchived && !$0.isDeleted }
            self.deletedNotes = notes.filter { $0.isDeleted }
            self.folders = folders.filter { !$0.isArchived }
            self.archivedFolders = folders.filter { $0.isArchived }

            // Re-index in Spotlight
            for note in self.notes {
                SpotlightIndexer.shared.indexNote(note)
            }

            logger.info("Imported backup: \(notes.count) notes, \(folders.count) folders")
        } catch {
            logger.error("Failed to import backup: \(error)")
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
            let predicate = #Predicate<NoteEntity> {
                $0.isArchived == false && $0.isDeleted == false
            }
            var descriptor = FetchDescriptor<NoteEntity>(
                predicate: predicate,
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
