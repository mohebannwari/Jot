//
//  NotesManager.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import Foundation
import Combine

@MainActor
final class NotesManager: ObservableObject {
    @Published var notes: [Note] = []

    private let storageURL: URL
    private let saveQueue = DispatchQueue(label: "com.jot.notes.save", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveCoalescingInterval: DispatchTimeInterval = .milliseconds(60)

    init(storageURL: URL? = nil, seedIfEmpty: Bool = true) {
        self.storageURL = storageURL ?? NotesManager.defaultStorageURL()
        load()
        if notes.isEmpty && seedIfEmpty {
            notes = NotesManager.seedNotes()
            save()
        }
        
        // Clean up orphaned images on app launch
        Task {
            await cleanupOrphanedImages()
        }
    }
    
    // MARK: - CRUD
    @discardableResult
    func addNote(title: String = "Untitled", content: String = "", tags: [String] = []) -> Note {
        var note = Note(title: title, content: content, tags: tags)
        note.date = Date()
        notes.insert(note, at: 0)
        save()
        return note
    }
    
    func updateNote(_ updated: Note) {
        if let idx = notes.firstIndex(where: { $0.id == updated.id }) {
            notes[idx] = updated
            save()
        }
    }
    
    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
        
        // Clean up orphaned images after deletion
        Task {
            await cleanupOrphanedImages()
        }
    }

    func togglePin(id: UUID) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].isPinned.toggle()
            save()
        }
    }

    func replaceAll(_ newNotes: [Note]) {
        notes = newNotes
        save()
    }
    
    // MARK: - Persistence
    private func load() {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: storageURL.path) {
                notes = []
                return
            }
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([Note].self, from: data)
            notes = decoded
        } catch {
            // If decoding fails, start fresh but don't overwrite corrupt file immediately
            notes = []
        }
    }
    
    private func save() {
        let snapshot = notes
        let destinationURL = storageURL

        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [snapshot, destinationURL] in
            do {
                let fm = FileManager.default
                let dir = destinationURL.deletingLastPathComponent()
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: destinationURL, options: [.atomic])
            } catch {
                // Silently ignore for now; in production surface this to the UI/logs
            }
        }

        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveCoalescingInterval, execute: workItem)
    }
    
    // MARK: - Helpers
    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Jot", isDirectory: true).appendingPathComponent("notes.json")
    }

    static func getStorageURL() -> URL {
        return defaultStorageURL()
    }
    
    private static func seedNotes() -> [Note] {
        return [
            Note(title: "Recent activities",
                 content: "The rain pattered softly against the attic window as I opened my journal. Dust motes danced in the single shaft of sunlight illuminating the aged pages. I picked up my pen, the nib scratching against the paper as I began to write. Today, I stumbled upon an old music box in the antique shop. Its melody was hauntingly familiar, like a forgotten dream.\n\n[[webclip|Exciting Recent Activities to Explore|Raindrops gently tapped the attic window while a single beam of light cut the dust.|funadventures.com]]",
                 tags: ["New", "Hobbys"]),
            Note(title: "Upcoming adventures",
                 content: "As the morning light filtered through the curtains, I brewed a cup of herbal tea and flipped through my travel journal. My heart raced with excitement as I mapped out my next journey to the coastal town of Port Haven. The salty breeze and the sound of waves crashing against the cliffs beckoned me.",
                 tags: ["Planned", "Travel"]),
            Note(title: "Creative projects",
                 content: "At my desk, surrounded by sketchbooks and paints, I felt a surge of inspiration. I decided to start a mural in my living room, depicting a vibrant forest scene. Each stroke of the brush transported me into a world of color and imagination.",
                 tags: ["Active", "Art"]),
            Note(title: "Community events",
                 content: "A flyer caught my attention while walking through the park, advertising the upcoming local festival. It promised an array of food stalls, live music, and workshops. Excitement bubbled within me as I envisioned the vibrant atmosphere, filled with laughter and creativity.",
                 tags: ["Community"]),
            Note(title: "Personal reflections",
                 content: "On this quiet evening, I took a moment to reflect on my life choices. Sitting in my favorite armchair with a cozy blanket, I pondered the paths I've taken. The experiences I've had, both good and bad, shaped who I am today."),
            Note(title: "Culinary experiments",
                 content: "With a fresh batch of organic vegetables from the local market, I decided to experiment in the kitchen. I envisioned a colorful stir-fry, packed with flavors and nutrients. As I chopped the vegetables, I could almost hear Elara's excitement about trying new recipes.",
                 tags: ["Completed", "Cooking"]),
            Note(title: "Fitness goals",
                 content: "The sun was just peeking over the horizon as I laced up my sneakers for a morning run. I set a goal to increase my distance this month, pushing my limits while enjoying the crisp morning air. Each step felt liberating, the rhythm of my breath syncing with the heartbeat of the world around me.",
                 tags: ["Active", "Fitness"])
        ]
    }
    
    // MARK: - Image Cleanup
    
    /// Clean up images that are no longer referenced in any notes
    private func cleanupOrphanedImages() async {
        await ImageStorageManager.shared.cleanupUnusedImages(referencedInNotes: notes)
    }
}
