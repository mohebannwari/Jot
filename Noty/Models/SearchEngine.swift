//
//  SearchEngine.swift
//  Noty
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
    
    // Data
    private var allNotes: [Note] = []
    
    // Internals
    private var cancellables = Set<AnyCancellable>()
    private let debounceMs: Int = 250
    
    init() {
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
    
    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        let lower = trimmed.lowercased()
        let tagQuery = lower.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hasDistinctTagQuery = tagQuery != lower && !tagQuery.isEmpty
        let hits = allNotes.compactMap { note -> SearchHit? in
            var score = 0
            var matchType: MatchType = .content
            var titleRange: Range<String.Index>?
            var contentRange: Range<String.Index>?
            
            if let r = note.title.lowercased().range(of: lower) {
                score += 100
                matchType = .title
                titleRange = r
            } else if hasDistinctTagQuery, let r = note.title.lowercased().range(of: tagQuery) {
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

            if let r = note.content.lowercased().range(of: lower) {
                score += 10
                if matchType == .content { contentRange = r }
            } else if hasDistinctTagQuery, let r = note.content.lowercased().range(of: tagQuery) {
                score += 10
                if matchType == .content { contentRange = r }
            }
            guard score > 0 else { return nil }
            return SearchHit(note: note, type: matchType, score: score, titleRange: titleRange, contentRange: contentRange, query: lower)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.note.date > rhs.note.date
        }
        results = Array(hits.prefix(20))
    }
}

// MARK: - Models

struct SearchHit: Identifiable, Equatable {
    let id = UUID()
    let note: Note
    let type: MatchType
    let score: Int
    let titleRange: Range<String.Index>?
    let contentRange: Range<String.Index>?
    let query: String
    
    static func == (lhs: SearchHit, rhs: SearchHit) -> Bool {
        lhs.id == rhs.id
    }
    
    var preview: String {
        let content = note.content
        guard let r = contentRange else { return String(content.prefix(140)) + (content.count > 140 ? "..." : "") }
        let start = content.index(r.lowerBound, offsetBy: -min(30, content.distance(from: content.startIndex, to: r.lowerBound)), limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(r.upperBound, offsetBy: min(90, content.distance(from: r.upperBound, to: content.endIndex)), limitedBy: content.endIndex) ?? content.endIndex
        let slice = content[start..<end]
        return (start > content.startIndex ? "..." : "") + slice + (end < content.endIndex ? "..." : "")
    }
}

enum MatchType { case title, content, tag }

