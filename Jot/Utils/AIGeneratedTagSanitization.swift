//
//  AIGeneratedTagSanitization.swift
//  Jot
//
//  Post-processes on-device model output for auto-tags: cap count, dedupe, and
//  strip overlaps with user tags. Pure functions — unit tested.
//

import Foundation

enum AIGeneratedTagSanitization {
    static let maxAITags: Int = 3

    /// Trims, drops empties, keeps first-seen casing per case-insensitive key (max `maxAITags`),
    /// and removes any string that matches `userTags` (case-insensitive).
    static func sanitize(suggested: [String], userTags: [String]) -> [String] {
        let userLower = Set(userTags.map { $0.lowercased() })
        var seenLower: Set<String> = []
        var out: [String] = []
        for raw in suggested {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let low = t.lowercased()
            if userLower.contains(low) { continue }
            if seenLower.contains(low) { continue }
            seenLower.insert(low)
            out.append(t)
            if out.count == Self.maxAITags { break }
        }
        return out
    }
}
