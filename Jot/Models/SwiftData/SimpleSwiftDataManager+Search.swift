import Foundation
import OSLog
import SwiftData

extension SimpleSwiftDataManager {
    // MARK: - Search

    /// Global search match including tags. SwiftData predicates cannot search `[String]` tags safely, so
    /// `searchNotes` uses a title/content fetch then merges tag hits from the loaded `notes` list.
    private func noteMatchesGlobalSearch(
        _ note: Note,
        normalizedQuery: String,
        allTerms: [String],
        sanitizedTagQuery: String,
        hasDistinctTagQuery: Bool
    ) -> Bool {
        let titleMatches = note.title.localizedCaseInsensitiveContains(normalizedQuery) ||
            (hasDistinctTagQuery && note.title.localizedCaseInsensitiveContains(sanitizedTagQuery))
        let contentMatches = note.content.localizedCaseInsensitiveContains(normalizedQuery) ||
            (hasDistinctTagQuery && note.content.localizedCaseInsensitiveContains(sanitizedTagQuery))
        let tagMatchesPrimary = note.tags.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        let tagMatchesFallback =
            hasDistinctTagQuery
            && note.tags.contains { $0.localizedCaseInsensitiveContains(sanitizedTagQuery) }

        guard titleMatches || contentMatches || tagMatchesPrimary || tagMatchesFallback else {
            return false
        }

        if allTerms.count > 1 {
            let tagBlob = note.tags.joined(separator: " ").lowercased()
            let haystack = (note.title + " " + note.content + " " + tagBlob).lowercased()
            return allTerms.allSatisfy { haystack.contains($0) }
        }
        return true
    }

    func searchNotes(query: String, limit: Int = 100) async -> [Note] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return notes.filter { !$0.isLocked }
        }

        let sanitizedTagQuery = normalizedQuery.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = sanitizedTagQuery != normalizedQuery && !sanitizedTagQuery.isEmpty

        let allTerms = normalizedQuery.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        do {
            let predicate = NoteEntity.searchPredicate(for: normalizedQuery)
            let sortDescriptors = NoteEntity.sortByRelevance(query: normalizedQuery)
            var descriptor = FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
            // Fetch extra rows so tag-only supplements can still fill `limit` after merging.
            descriptor.fetchLimit = max(limit * 4, limit + 50)

            let entities = try modelContext.fetch(descriptor)
            var results = entities.map { $0.toNote() }.filter { !$0.isLocked }

            // The predicate only matches the first term (SwiftData #Predicate
            // cannot loop over a dynamic array). Post-filter in memory for any
            // additional terms so that multi-word queries return correct results.
            if allTerms.count > 1 {
                results = results.filter { note in
                    let tagBlob = note.tags.joined(separator: " ").lowercased()
                    let haystack = (note.title + " " + note.content + " " + tagBlob).lowercased()
                    return allTerms.allSatisfy { haystack.contains($0) }
                }
            }

            let resultIDs = Set(results.map(\.id))
            let supplemental = notes.filter { note in
                guard !note.isLocked, !resultIDs.contains(note.id) else { return false }
                return noteMatchesGlobalSearch(
                    note,
                    normalizedQuery: normalizedQuery,
                    allTerms: allTerms,
                    sanitizedTagQuery: sanitizedTagQuery,
                    hasDistinctTagQuery: hasDistinctTagQuery
                )
            }
            results.append(contentsOf: supplemental)
            results.sort { $0.date > $1.date }

            let capped = Array(results.prefix(limit))
            logger.info("Search for '\(query)' returned \(capped.count) results")
            return capped
        } catch {
            logger.error("Search failed: \(error)")
            let filtered = notes.filter { !$0.isLocked }.filter { note in
                noteMatchesGlobalSearch(
                    note,
                    normalizedQuery: normalizedQuery,
                    allTerms: allTerms,
                    sanitizedTagQuery: sanitizedTagQuery,
                    hasDistinctTagQuery: hasDistinctTagQuery
                )
            }
            return Array(filtered.sorted { $0.date > $1.date }.prefix(limit))
        }
    }


}
