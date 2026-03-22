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
    @Published private(set) var recentQueries: [String]
    
    // Data
    private var allNotes: [Note] = []
    private var allFolders: [Folder] = []
    
    // Internals
    private var cancellables = Set<AnyCancellable>()
    private let debounceMs: Int = 250
    private let maxRecentQueries = 3
    private let userDefaults: UserDefaults
    private let recentQueriesKey: String
    
    init(
        userDefaults: UserDefaults = .standard,
        recentQueriesKey: String = "SearchEngine.recentQueries"
    ) {
        self.userDefaults = userDefaults
        self.recentQueriesKey = recentQueriesKey
        let persistedQueries = userDefaults.stringArray(forKey: recentQueriesKey) ?? []
        self.recentQueries = SearchEngine.normalizedRecentQueries(
            persistedQueries,
            maxCount: maxRecentQueries
        )

        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(debounceMs), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.performSearch() }
            .store(in: &cancellables)
    }
    
    func setNotes(_ notes: [Note]) {
        allNotes = notes
        performSearch()
    }

    func setFolders(_ folders: [Folder]) {
        allFolders = folders
        performSearch()
    }

    func recordCommittedQuery(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        recentQueries = SearchEngine.normalizedRecentQueries(
            [trimmed] + recentQueries,
            maxCount: maxRecentQueries
        )
        userDefaults.set(recentQueries, forKey: recentQueriesKey)
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

            let stripped = note.content.strippingAllMarkup

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
}

// MARK: - Models

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
