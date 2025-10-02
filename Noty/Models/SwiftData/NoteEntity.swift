import Foundation
import SwiftData

@Model
final class NoteEntity {
    // MARK: - Core Properties
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \TagEntity.notes)
    var tags: [TagEntity] = []

    // MARK: - Computed Properties for Search
    @Transient
    var searchableContent: String {
        let tagNames = tags.map { $0.name }.joined(separator: " ")
        return "\(title) \(content) \(tagNames)".lowercased()
    }

    @Transient
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt)
    }

    @Transient
    var tagNames: [String] {
        tags.map { $0.name }.sorted()
    }

    // MARK: - Performance Optimized Properties
    @Transient
    var contentPreview: String {
        let maxLength = 150
        if content.count <= maxLength {
            return content
        }
        let truncated = String(content.prefix(maxLength))
        return truncated + "..."
    }

    @Transient
    var wordCount: Int {
        content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    // MARK: - Web Clip Support
    var webClipURL: String?
    var webClipTitle: String?
    var webClipDescription: String?

    @Transient
    var isWebClip: Bool {
        webClipURL != nil
    }

    // MARK: - Search and Indexing Support
    // Note: Index macros should be applied at class level, moving to init

    // MARK: - Initialization
    init(title: String, content: String, createdAt: Date, modifiedAt: Date) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.webClipURL = nil
        self.webClipTitle = nil
        self.webClipDescription = nil
    }

    // MARK: - Convenience Initializers
    convenience init(title: String, content: String) {
        let now = Date()
        self.init(title: title, content: content, createdAt: now, modifiedAt: now)
    }

    convenience init(from note: Note) {
        self.init(
            title: note.title,
            content: note.content,
            createdAt: note.date,
            modifiedAt: note.date
        )
        self.id = note.id

        // Extract web clip data from content if present
        self.extractWebClipData()
    }

    // MARK: - Web Clip Processing
    func setWebClipData(url: String, title: String?, description: String?) {
        self.webClipURL = url
        self.webClipTitle = title
        self.webClipDescription = description
        self.modifiedAt = Date()
    }

    private func extractWebClipData() {
        // Extract webclip data from legacy content format
        // Format: [[webclip|title|description|url]]
        let pattern = #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        if let match = regex.firstMatch(in: content, range: range) {
            if match.numberOfRanges >= 4 {
                let titleRange = match.range(at: 1)
                let descRange = match.range(at: 2)
                let urlRange = match.range(at: 3)

                if let titleSubstring = Range(titleRange, in: content),
                   let descSubstring = Range(descRange, in: content),
                   let urlSubstring = Range(urlRange, in: content) {

                    self.webClipTitle = String(content[titleSubstring])
                    self.webClipDescription = String(content[descSubstring])
                    self.webClipURL = String(content[urlSubstring])

                    // Remove the webclip markup from content
                    self.content = content.replacingOccurrences(of: content[Range(match.range, in: content)!], with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    // MARK: - Update Methods
    func updateContent(_ newContent: String) {
        self.content = newContent
        self.modifiedAt = Date()
        self.extractWebClipData()
    }

    func updateTitle(_ newTitle: String) {
        self.title = newTitle
        self.modifiedAt = Date()
    }

    func addTag(_ tag: TagEntity) {
        if !tags.contains(tag) {
            tags.append(tag)
            // Maintain bidirectional relationship
            if !tag.notes.contains(self) {
                tag.notes.append(self)
            }
            modifiedAt = Date()
        }
    }

    func removeTag(_ tag: TagEntity) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
            // Maintain bidirectional relationship
            if let noteIndex = tag.notes.firstIndex(of: self) {
                tag.notes.remove(at: noteIndex)
            }
            modifiedAt = Date()
        }
    }

    func setTags(_ tagNames: [String], in context: ModelContext) {
        // Clear existing tags
        tags.removeAll()

        // Add new tags (create if they don't exist)
        for tagName in tagNames {
            let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            // Try to find existing tag
            let predicate = #Predicate<TagEntity> { $0.name == trimmedName }
            let descriptor = FetchDescriptor(predicate: predicate)

            do {
                let existingTags = try context.fetch(descriptor)
                let tag = existingTags.first ?? TagEntity(name: trimmedName)

                if existingTags.isEmpty {
                    context.insert(tag)
                }

                addTag(tag)
            } catch {
                // If fetch fails, create new tag
                let newTag = TagEntity(name: trimmedName)
                context.insert(newTag)
                addTag(newTag)
            }
        }

        modifiedAt = Date()
    }

    // MARK: - Export/Conversion
    func toNote() -> Note {
        var note = Note(title: title, content: content, tags: tagNames)
        note.id = id
        note.date = modifiedAt
        return note
    }
}

// MARK: - Search Extensions
extension NoteEntity {
    static func searchPredicate(for query: String) -> Predicate<NoteEntity> {
        let searchTerms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !searchTerms.isEmpty else {
            return #Predicate<NoteEntity> { _ in false }
        }

        // Simplified predicate to avoid complex subqueries that SwiftData doesn't support
        let firstTerm = searchTerms.first!
        return #Predicate<NoteEntity> { note in
            note.title.localizedStandardContains(firstTerm) ||
            note.content.localizedStandardContains(firstTerm)
        }
    }

    static func recentNotesPredicate(days: Int = 30) -> Predicate<NoteEntity> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return #Predicate<NoteEntity> { note in
            note.modifiedAt >= cutoffDate
        }
    }

    static func sortByRelevance(query: String) -> [SortDescriptor<NoteEntity>] {
        // Primary sort by modification date (most recent first)
        // Future: implement relevance scoring
        return [
            SortDescriptor(\.modifiedAt, order: .reverse),
            SortDescriptor(\.createdAt, order: .reverse)
        ]
    }
}