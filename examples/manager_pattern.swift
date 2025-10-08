//
//  manager_pattern.swift
//  Noty Examples
//
//  Simplified pattern extracted from: Noty/Models/NotesManager.swift
//
//  This demonstrates the standard manager structure for state management
//  and data persistence in the Noty app.
//

import Foundation
import Combine

// MARK: - Manager Pattern

/// Example manager following Noty's established pattern:
/// - @MainActor ensures all operations run on main thread
/// - ObservableObject enables SwiftUI to observe changes
/// - @Published properties trigger UI updates automatically
/// - Handles business logic and data persistence
@MainActor
final class ExampleManager: ObservableObject {
    // MARK: - Published Properties
    // Any UI-visible state that triggers updates
    @Published var items: [ExampleItem] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    // Internal state not exposed to UI
    private let storageURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initialize with optional storage URL and seed data option
    /// - Parameters:
    ///   - storageURL: Custom storage location (defaults to app support directory)
    ///   - seedIfEmpty: Whether to populate with seed data if empty
    init(storageURL: URL? = nil, seedIfEmpty: Bool = true) {
        // Use provided URL or default location
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        
        // Load existing data from disk
        load()
        
        // Optionally seed with initial data
        if items.isEmpty && seedIfEmpty {
            items = Self.seedData()
            save()
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new item
    /// - Parameters:
    ///   - title: Item title
    ///   - content: Item content
    /// - Returns: The created item
    @discardableResult
    func addItem(title: String, content: String) -> ExampleItem {
        let item = ExampleItem(title: title, content: content)
        // Insert at beginning for recency
        items.insert(item, at: 0)
        // Persist changes immediately
        save()
        return item
    }
    
    /// Update an existing item
    /// - Parameter updated: The updated item
    func updateItem(_ updated: ExampleItem) {
        // Find item by ID and replace
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = updated
            save()
        }
    }
    
    /// Delete an item by ID
    /// - Parameter id: The item's unique identifier
    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }
    
    /// Replace all items (useful for restore/import)
    /// - Parameter newItems: The new items array
    func replaceAll(_ newItems: [ExampleItem]) {
        items = newItems
        save()
    }
    
    // MARK: - Persistence
    
    /// Load items from disk storage
    private func load() {
        do {
            let fileManager = FileManager.default
            
            // Check if file exists
            guard fileManager.fileExists(atPath: storageURL.path) else {
                items = []
                return
            }
            
            // Read and decode data
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([ExampleItem].self, from: data)
            items = decoded
        } catch {
            // On decode error, start fresh but don't overwrite corrupt file
            // In production, log this error or surface to UI
            print("Failed to load data: \(error)")
            items = []
        }
    }
    
    /// Save items to disk storage
    private func save() {
        do {
            let fileManager = FileManager.default
            let directory = storageURL.deletingLastPathComponent()
            
            // Create directory if needed
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            
            // Encode and write data atomically
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // In production, surface this error to user
            // For now, silently ignore to prevent crashes
            print("Failed to save data: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    /// Default storage location in app support directory
    /// - Returns: URL for the storage file
    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        return appSupport
            .appendingPathComponent("Noty", isDirectory: true)
            .appendingPathComponent("example_data.json")
    }
    
    /// Generate seed data for initial app state
    /// - Returns: Array of sample items
    private static func seedData() -> [ExampleItem] {
        return [
            ExampleItem(
                title: "Welcome to Noty",
                content: "Start organizing your thoughts with beautiful notes."
            ),
            ExampleItem(
                title: "Getting Started",
                content: "Create new notes, add tags, and organize everything."
            )
        ]
    }
}

// MARK: - Supporting Model

/// Example model conforming to Codable for persistence
/// and Identifiable for SwiftUI list handling
struct ExampleItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var createdDate: Date
    
    init(id: UUID = UUID(), title: String, content: String, createdDate: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdDate = createdDate
    }
}

// MARK: - Key Takeaways

/*
 Manager Pattern Structure:
 
 1. CLASS DECLARATION
    - @MainActor ensures thread safety for UI operations
    - final prevents subclassing
    - ObservableObject enables SwiftUI observation
 
 2. PUBLISHED PROPERTIES
    - Use @Published for any state that affects UI
    - UI automatically updates when these change
    - Keep public for view access
 
 3. PRIVATE PROPERTIES
    - Internal state not exposed to views
    - Storage configuration
    - Utilities like Combine cancellables
 
 4. INITIALIZATION
    - Accept optional dependencies (storage URL)
    - Load existing data
    - Seed initial data if needed
    - Keep logic minimal, delegate to helper methods
 
 5. CRUD OPERATIONS
    - Public methods for all data operations
    - Always call save() after modifying data
    - Use @discardableResult when returning created items
    - Find items by ID for updates/deletes
 
 6. PERSISTENCE
    - Private load() and save() methods
    - Use JSON encoding for simple data
    - Handle errors gracefully (don't crash)
    - Create directories as needed
    - Use atomic writes to prevent corruption
 
 7. HELPERS
    - Static methods for configuration (defaultStorageURL)
    - Static methods for seed data generation
    - Keep business logic encapsulated
 
 State Management Flow:
 
 View → Action → Manager Method → Update @Published → Save → UI Update
 
 Example:
 User taps delete → deleteItem(id) → items.removeAll → save() → UI refreshes
 
 Testing Pattern:
 - Inject custom storageURL for isolated tests
 - Use temporary directory
 - Disable seeding for clean slate
 - Verify persistence by creating new manager instance
 
 Error Handling:
 - Catch decode errors (corrupt data)
 - Catch file system errors (permissions)
 - Log errors for debugging
 - Don't crash the app
 - Surface critical errors to UI
 
 Thread Safety:
 - @MainActor ensures all methods run on main thread
 - No manual thread switching needed
 - Safe for UI updates
 - Required for @Published properties
 */

