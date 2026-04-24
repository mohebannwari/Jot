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
    var suppressDerivedRecompute = false
    @Published var archivedNotes: [Note] = []
    @Published var deletedNotes: [Note] = []
    @Published var folders: [Folder] = []
    @Published var archivedFolders: [Folder] = []
    @Published var smartFolders: [SmartFolder] = []

    // Sidebar groupings — recomputed only when notes change, not on every UI state change.
    // NOT @Published — objectWillChange is sent once manually in recomputeDerivedNotes()
    // to avoid 9 separate SwiftUI invalidation passes per note save.
    var notesByFolderID: [UUID: [Note]] = [:]
    /// Virtual folder membership from smart-folder predicates (keys are smart-folder IDs).
    var notesBySmartFolderID: [UUID: [Note]] = [:]
    var unfiledNotes: [Note] = []
    var pinnedNotes: [Note] = []
    var lockedNotes: [Note] = []
    var todayNotes: [Note] = []
    var thisMonthNotes: [Note] = []
    var thisYearNotes: [Note] = []
    var olderNotes: [Note] = []
    var allUnpinnedNotes: [Note] = []
    @Published private(set) var hasLoadedInitialNotes = false
    @Published private(set) var hasCompletedMigrationCheck = false

    private let modelContainer: ModelContainer
    private(set) var modelContext: ModelContext
    let logger = Logger(subsystem: "com.jot.app", category: "SimpleSwiftDataManager")
    static let encoder = JSONEncoder()

    // MARK: - Performance Configuration
    let batchSize = 50
    let maxLoadLimit = 500

    func markInitialNotesLoaded() {
        hasLoadedInitialNotes = true
    }

    /// Creates a manager backed by an in-memory store for use in unit tests only.
    /// Never call this in production code.
    init(inMemoryForTesting: Bool) throws {
        precondition(inMemoryForTesting, "Use init() for production; this overload is tests-only")
        let schema = Schema([NoteEntity.self, FolderEntity.self, NoteVersionEntity.self, SmartFolderEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        hasLoadedInitialNotes = true
        hasCompletedMigrationCheck = true
    }

    /// Creates a manager backed by a real on-disk store at a test-controlled URL.
    /// Never call this in production code.
    init(storeURLForTesting storeURL: URL) throws {
        let schema = Schema([NoteEntity.self, FolderEntity.self, NoteVersionEntity.self, SmartFolderEntity.self])
        let configuration = ModelConfiguration(
            "JotTests",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = true

        hasLoadedInitialNotes = false
        hasCompletedMigrationCheck = true
        loadFolders()

        Task { @MainActor in
            self.loadNotes(isInitialLoad: true)
        }
    }

    init() throws {
        // Setup SwiftData container
        let schema = Schema([NoteEntity.self, FolderEntity.self, NoteVersionEntity.self, SmartFolderEntity.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.modelContext = ModelContext(modelContainer)

        // Configure main context for UI
        modelContext.autosaveEnabled = true

        // Load initial data
        hasLoadedInitialNotes = false
        hasCompletedMigrationCheck = true
        loadFolders()

        Task { @MainActor in
            self.loadNotes(isInitialLoad: true)
        }
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
