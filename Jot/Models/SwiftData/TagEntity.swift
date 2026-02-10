import Foundation
import SwiftData

@Model
final class TagEntity {
    // MARK: - Core Properties
    @Attribute(.unique) var name: String
    var createdAt: Date
    var usageCount: Int = 0

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var notes: [NoteEntity] = []

    // MARK: - Computed Properties
    @Transient
    var displayName: String {
        name.capitalized
    }

    @Transient
    var isActive: Bool {
        !notes.isEmpty
    }

    @Transient
    var lastUsed: Date? {
        notes.map { $0.modifiedAt }.max()
    }

    @Transient
    var noteCount: Int {
        notes.count
    }

    // MARK: - Performance Indices
    // Note: Index macros should be applied at class level

    // MARK: - Initialization
    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.createdAt = Date()
        self.usageCount = 0
    }

    // MARK: - Usage Tracking
    func incrementUsage() {
        usageCount += 1
    }

    func updateUsageCount() {
        usageCount = notes.count
    }

    // MARK: - Validation
    static func isValidTagName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 50
    }

    static func sanitizeTagName(_ name: String) -> String {
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}

// MARK: - Search and Query Extensions
extension TagEntity {
    static func popularTagsPredicate(limit: Int = 20) -> FetchDescriptor<TagEntity> {
        var descriptor = FetchDescriptor<TagEntity>(
            predicate: #Predicate<TagEntity> { tag in tag.usageCount > 0 },
            sortBy: [
                SortDescriptor(\.usageCount, order: .reverse),
                SortDescriptor(\.name, order: .forward)
            ]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    static func recentTagsPredicate(days: Int = 30) -> Predicate<TagEntity> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return #Predicate<TagEntity> { tag in
            tag.notes.contains { $0.modifiedAt >= cutoffDate }
        }
    }

    static func searchPredicate(for query: String) -> Predicate<TagEntity> {
        let searchTerm = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerm.isEmpty else {
            return #Predicate<TagEntity> { _ in false }
        }

        return #Predicate<TagEntity> { tag in
            tag.name.contains(searchTerm)
        }
    }

    static func unusedTagsPredicate() -> Predicate<TagEntity> {
        return #Predicate<TagEntity> { tag in
            tag.notes.isEmpty
        }
    }
}

// MARK: - Maintenance Extensions
extension TagEntity {
    /// Clean up unused tags older than specified days
    static func cleanupUnusedTags(in context: ModelContext, olderThanDays days: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let predicate = #Predicate<TagEntity> { tag in
            tag.notes.isEmpty && tag.createdAt < cutoffDate
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        let unusedTags = try context.fetch(descriptor)

        for tag in unusedTags {
            context.delete(tag)
        }
    }

    /// Update usage counts for all tags
    static func updateAllUsageCounts(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<TagEntity>()
        let allTags = try context.fetch(descriptor)

        for tag in allTags {
            tag.updateUsageCount()
        }
    }

    /// Merge duplicate tags (case-insensitive)
    static func mergeDuplicateTags(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<TagEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        let allTags = try context.fetch(descriptor)

        var tagGroups: [String: [TagEntity]] = [:]

        // Group tags by normalized name
        for tag in allTags {
            let normalizedName = tag.name.lowercased()
            tagGroups[normalizedName, default: []].append(tag)
        }

        // Merge duplicates
        for (_, tags) in tagGroups where tags.count > 1 {
            let primaryTag = tags.first!
            let duplicates = Array(tags.dropFirst())

            // Move all notes from duplicates to primary tag
            for duplicate in duplicates {
                for note in duplicate.notes {
                    if !primaryTag.notes.contains(note) {
                        primaryTag.notes.append(note)
                    }
                }
                context.delete(duplicate)
            }

            // Update usage count
            primaryTag.updateUsageCount()
        }
    }
}