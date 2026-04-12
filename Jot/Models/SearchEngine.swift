//
//  SearchEngine.swift
//  Jot
//
//  Created by AI on 08.08.25.
//
//  A minimal, clean search engine with debouncing and simple relevance scoring.
//  Designed to power the new FloatingSearch overlay.

import Foundation
import Combine

@MainActor
final class SearchEngine: ObservableObject {
    // Input
    @Published var query: String = ""

    // Outputs
    @Published private(set) var results: [SearchHit] = []
    /// Combined LAST SEARCH rows (queries + opened targets), newest first, max `maxPaletteHistoryCount`.
    @Published private(set) var paletteHistory: [SearchPaletteHistoryEntry]

    // Data
    private var allNotes: [Note] = []
    private var allFolders: [Folder] = []
    /// Cache stripped content to avoid re-stripping on every search keystroke
    private var strippedContentCache: [UUID: (hash: Int, stripped: String)] = [:]

    // Internals
    private var cancellables = Set<AnyCancellable>()
    private let debounceMs: Int = 250
    private static let maxPaletteHistoryCount = 5
    private let userDefaults: UserDefaults
    /// Legacy keys — read once for migration, then cleared.
    private let recentQueriesKey: String
    private let recentOpenedFromSearchKey: String
    private let paletteHistoryKey: String

    init(
        userDefaults: UserDefaults = .standard,
        recentQueriesKey: String = "SearchEngine.recentQueries",
        recentOpenedFromSearchKey: String = "SearchEngine.recentOpenedFromSearch",
        paletteHistoryKey: String = "SearchEngine.paletteHistory"
    ) {
        self.userDefaults = userDefaults
        self.recentQueriesKey = recentQueriesKey
        self.recentOpenedFromSearchKey = recentOpenedFromSearchKey
        self.paletteHistoryKey = paletteHistoryKey
        self.paletteHistory = SearchEngine.loadPaletteHistory(
            userDefaults: userDefaults,
            recentQueriesKey: recentQueriesKey,
            recentOpenedFromSearchKey: recentOpenedFromSearchKey,
            paletteHistoryKey: paletteHistoryKey
        )

        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceMs), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.performSearch() }
            .store(in: &cancellables)
    }
    
    func setNotes(_ notes: [Note]) {
        allNotes = notes
        // Invalidate stale cache entries for notes that changed
        for note in notes {
            let hash = note.content.hashValue
            if strippedContentCache[note.id]?.hash != hash {
                strippedContentCache[note.id] = nil
            }
        }
        let validNoteIDs = Set(notes.map(\.id))
        pruneRecentOpenedNoteTargets(validNoteIDs: validNoteIDs)
        performSearch()
    }

    func setFolders(_ folders: [Folder]) {
        allFolders = folders
        let validFolderIDs = Set(folders.map(\.id))
        pruneRecentOpenedFolderTargets(validFolderIDs: validFolderIDs)
        performSearch()
    }

    func recordCommittedQuery(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var next = paletteHistory
        next.removeAll { entry in
            guard let q = entry.queryText else { return false }
            return q.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        next.append(SearchPaletteHistoryEntry(queryText: trimmed))
        paletteHistory = Self.sortedCappedHistory(next)
        persistPaletteHistory()
    }

    /// Call when the user opens a note from the global search palette (in addition to `recordCommittedQuery`).
    func recordOpenedFromSearch(note: Note) {
        recordOpenedFromSearch(
            RecentOpenedSearchTarget(kind: .note, entityID: note.id, title: note.title))
    }

    /// Call when the user opens a folder from the global search palette (in addition to `recordCommittedQuery`).
    func recordOpenedFromSearch(folder: Folder) {
        recordOpenedFromSearch(
            RecentOpenedSearchTarget(kind: .folder, entityID: folder.id, title: folder.name))
    }

    private func recordOpenedFromSearch(_ entry: RecentOpenedSearchTarget) {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let normalizedEntry = RecentOpenedSearchTarget(
            kind: entry.kind, entityID: entry.entityID, title: trimmedTitle)
        var next = paletteHistory.filter { $0.openedTarget?.entityID != normalizedEntry.entityID }
        next.append(SearchPaletteHistoryEntry(openedTarget: normalizedEntry))
        paletteHistory = Self.sortedCappedHistory(next)
        persistPaletteHistory()
    }

    /// Removes a stale row when the note/folder no longer exists (e.g. user tapped a ghost recent).
    func removeRecentOpenedTarget(entityID: UUID) {
        let filtered = paletteHistory.filter { $0.openedTarget?.entityID != entityID }
        guard filtered.count != paletteHistory.count else { return }
        paletteHistory = filtered
        persistPaletteHistory()
    }

    private func persistPaletteHistory() {
        if let data = try? JSONEncoder().encode(paletteHistory) {
            userDefaults.set(data, forKey: paletteHistoryKey)
        }
    }

    /// Drop note targets that no longer exist (folders left untouched so early `setNotes` does not wipe folder recents).
    private func pruneRecentOpenedNoteTargets(validNoteIDs: Set<UUID>) {
        let filtered = paletteHistory.filter { entry in
            guard let t = entry.openedTarget else { return true }
            if t.kind == .note { return validNoteIDs.contains(t.entityID) }
            return true
        }
        guard filtered.count != paletteHistory.count else { return }
        paletteHistory = filtered
        persistPaletteHistory()
    }

    /// Drop folder targets that no longer exist (notes left untouched for the symmetric reason).
    private func pruneRecentOpenedFolderTargets(validFolderIDs: Set<UUID>) {
        let filtered = paletteHistory.filter { entry in
            guard let t = entry.openedTarget else { return true }
            if t.kind == .folder { return validFolderIDs.contains(t.entityID) }
            return true
        }
        guard filtered.count != paletteHistory.count else { return }
        paletteHistory = filtered
        persistPaletteHistory()
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        let lower = trimmed.lowercased()
        let tagQuery = lower.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = tagQuery != lower && !tagQuery.isEmpty
        let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        
        let noteHits = allNotes.compactMap { note -> SearchHit? in
            var score = 0
            var matchType: MatchType = .content
            var titleRange: Range<String.Index>?
            var contentRange: Range<String.Index>?

            if let r = note.title.range(of: trimmed, options: searchOptions) {
                score += 100
                matchType = .title
                titleRange = r
            } else if hasDistinctTagQuery, let r = note.title.range(of: tagQuery, options: searchOptions) {
                score += 100
                matchType = .title
                titleRange = r
            }

            let tagMatchesPrimary = note.tags.contains { $0.lowercased().contains(lower) }
            let tagMatchesFallback = hasDistinctTagQuery && note.tags.contains { $0.lowercased().contains(tagQuery) }
            if tagMatchesPrimary || tagMatchesFallback {
                score += 50
                if matchType == .content { matchType = .tag }
            }

            let stripped: String
            let contentHash = note.content.hashValue
            if let cached = strippedContentCache[note.id], cached.hash == contentHash {
                stripped = cached.stripped
            } else {
                stripped = note.content.strippingAllMarkup
                strippedContentCache[note.id] = (hash: contentHash, stripped: stripped)
            }

            if let r = stripped.range(of: trimmed, options: searchOptions) {
                score += 10
                if matchType == .content { contentRange = r }
            } else if hasDistinctTagQuery, let r = stripped.range(of: tagQuery, options: searchOptions) {
                score += 10
                if matchType == .content { contentRange = r }
            }
            guard score > 0 else { return nil }
            return SearchHit(
                payload: .note(note),
                type: matchType,
                score: score,
                titleRange: titleRange,
                contentRange: contentRange,
                query: lower,
                strippedContent: stripped
            )
        }
        
        let folderHits = allFolders.compactMap { folder -> SearchHit? in
            var score = 0
            var titleRange: Range<String.Index>?
            
            if let r = folder.name.range(of: trimmed, options: searchOptions) {
                score += 120
                titleRange = r
            } else if hasDistinctTagQuery, let r = folder.name.range(of: tagQuery, options: searchOptions) {
                score += 120
                titleRange = r
            }
            
            guard score > 0 else { return nil }
            return SearchHit(
                payload: .folder(folder),
                type: .folder,
                score: score,
                titleRange: titleRange,
                contentRange: nil,
                query: lower,
                strippedContent: nil
            )
        }

        let hits = (noteHits + folderHits).sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.sortDate > rhs.sortDate
        }

        results = Array(hits.prefix(20))
    }

    private static func sortedCappedHistory(_ entries: [SearchPaletteHistoryEntry]) -> [SearchPaletteHistoryEntry] {
        let sorted = entries.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        return Array(sorted.prefix(maxPaletteHistoryCount))
    }

    /// Loads unified history, or migrates legacy `recentQueries` + `recentOpenedFromSearch` once (then clears legacy keys).
    private static func loadPaletteHistory(
        userDefaults: UserDefaults,
        recentQueriesKey: String,
        recentOpenedFromSearchKey: String,
        paletteHistoryKey: String
    ) -> [SearchPaletteHistoryEntry] {
        if let data = userDefaults.data(forKey: paletteHistoryKey),
            let decoded = try? JSONDecoder().decode([SearchPaletteHistoryEntry].self, from: data),
            !decoded.isEmpty
        {
            return sortedCappedHistory(decoded)
        }

        let legacyQueriesRaw = userDefaults.stringArray(forKey: recentQueriesKey) ?? []
        let legacyQueries = normalizedRecentQueries(legacyQueriesRaw, maxCount: 50)
        var legacyOpened: [RecentOpenedSearchTarget] = []
        if let openedData = userDefaults.data(forKey: recentOpenedFromSearchKey),
            let decoded = try? JSONDecoder().decode([RecentOpenedSearchTarget].self, from: openedData)
        {
            legacyOpened = normalizedRecentOpened(decoded, maxCount: 50)
        }

        let hadLegacy =
            !legacyQueriesRaw.isEmpty || userDefaults.data(forKey: recentOpenedFromSearchKey) != nil
        guard hadLegacy else { return [] }

        var merged: [SearchPaletteHistoryEntry] = []
        var time = Date().timeIntervalSince1970
        for q in legacyQueries {
            guard merged.count < maxPaletteHistoryCount else { break }
            merged.append(
                SearchPaletteHistoryEntry(
                    recordedAt: Date(timeIntervalSince1970: time), queryText: q))
            time -= 0.001
        }
        for o in legacyOpened {
            guard merged.count < maxPaletteHistoryCount else { break }
            merged.append(
                SearchPaletteHistoryEntry(recordedAt: Date(timeIntervalSince1970: time), openedTarget: o))
            time -= 0.001
        }
        let normalized = sortedCappedHistory(merged)
        userDefaults.removeObject(forKey: recentQueriesKey)
        userDefaults.removeObject(forKey: recentOpenedFromSearchKey)
        if let data = try? JSONEncoder().encode(normalized) {
            userDefaults.set(data, forKey: paletteHistoryKey)
        }
        return normalized
    }

    private static func normalizedRecentQueries(_ queries: [String], maxCount: Int) -> [String] {
        var normalized: [String] = []
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isDuplicate = normalized.contains {
                $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard !isDuplicate else { continue }

            normalized.append(trimmed)
            if normalized.count == maxCount {
                break
            }
        }
        return normalized
    }

    private static func normalizedRecentOpened(
        _ items: [RecentOpenedSearchTarget], maxCount: Int
    ) -> [RecentOpenedSearchTarget] {
        var seen = Set<UUID>()
        var out: [RecentOpenedSearchTarget] = []
        for item in items {
            guard !seen.contains(item.entityID) else { continue }
            seen.insert(item.entityID)
            out.append(item)
            if out.count == maxCount { break }
        }
        return out
    }
}

// MARK: - Models

/// A note or folder the user opened from global search, shown under LAST SEARCH with the correct icon.
struct RecentOpenedSearchTarget: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case note
        case folder
    }

    var kind: Kind
    var entityID: UUID
    var title: String

    var id: UUID { entityID }
}

/// One row under LAST SEARCH: either a committed query string or a note/folder opened from the palette.
struct SearchPaletteHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var recordedAt: Date
    var queryText: String?
    var openedTarget: RecentOpenedSearchTarget?

    var isQuery: Bool { queryText != nil }

    init(id: UUID = UUID(), recordedAt: Date = Date(), queryText: String) {
        self.id = id
        self.recordedAt = recordedAt
        self.queryText = queryText
        self.openedTarget = nil
    }

    init(id: UUID = UUID(), recordedAt: Date = Date(), openedTarget: RecentOpenedSearchTarget) {
        self.id = id
        self.recordedAt = recordedAt
        self.queryText = nil
        self.openedTarget = openedTarget
    }
}

struct SearchHit: Identifiable, Equatable {
    let id = UUID()
    let payload: SearchPayload
    let type: MatchType
    let score: Int
    let titleRange: Range<String.Index>?
    let contentRange: Range<String.Index>?
    let query: String
    let strippedContent: String?
    
    static func == (lhs: SearchHit, rhs: SearchHit) -> Bool {
        lhs.id == rhs.id
    }

    var note: Note? {
        guard case let .note(note) = payload else { return nil }
        return note
    }

    var folder: Folder? {
        guard case let .folder(folder) = payload else { return nil }
        return folder
    }

    var title: String {
        switch payload {
        case let .note(note):
            return note.title
        case let .folder(folder):
            return folder.name
        }
    }

    var isFolderResult: Bool {
        folder != nil
    }

    var sortDate: Date {
        switch payload {
        case let .note(note):
            return note.date
        case let .folder(folder):
            return folder.modifiedAt
        }
    }
    
    var preview: String {
        guard let stripped = strippedContent else { return "" }
        guard let r = contentRange else {
            return String(stripped.prefix(140)) + (stripped.count > 140 ? "..." : "")
        }
        let start = stripped.index(r.lowerBound, offsetBy: -min(30, stripped.distance(from: stripped.startIndex, to: r.lowerBound)), limitedBy: stripped.startIndex) ?? stripped.startIndex
        let end = stripped.index(r.upperBound, offsetBy: min(90, stripped.distance(from: r.upperBound, to: stripped.endIndex)), limitedBy: stripped.endIndex) ?? stripped.endIndex
        let slice = String(stripped[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (start > stripped.startIndex ? "..." : "") + slice + (end < stripped.endIndex ? "..." : "")
    }
}

enum SearchPayload: Equatable {
    case note(Note)
    case folder(Folder)
}

enum MatchType { case title, content, tag, folder }
