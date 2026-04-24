//
//  OutgoingNotelinkScanner.swift
//  Jot
//
//  Scans serialized note content for `[[notelink|<uuid>|<title>]]` tokens.
//  Payload splitting must mirror `TodoEditorRepresentable+Deserializer` (maxSplits: 1 on `|`)
//  so titles containing `|` are preserved.
//

import Foundation

enum OutgoingNotelinkScanner {
    private static let openToken = "[[notelink|"

    /// Ordered unique targets referenced by `[[notelink|...]]` in the given content.
    /// - Parameters:
    ///   - content: Serialized note body.
    ///   - excludingNoteID: If provided, drops mentions whose target equals this id (e.g. self-mentions).
    static func outgoingNotelinks(in content: String, excludingNoteID: UUID? = nil) -> [(noteID: UUID, serializedTitle: String)] {
        guard content.contains(openToken) else { return [] }

        var seen = Set<UUID>()
        var results: [(UUID, String)] = []

        var searchStart = content.startIndex
        while let openRange = content.range(of: openToken, range: searchStart..<content.endIndex) {
            let afterOpen = openRange.upperBound
            guard let closeRange = content[afterOpen...].range(of: "]]") else { break }

            let body = String(content[afterOpen..<closeRange.lowerBound])
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                searchStart = closeRange.upperBound
                continue
            }

            let idString = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1])

            guard let noteID = UUID(uuidString: idString) else {
                searchStart = closeRange.upperBound
                continue
            }

            if let excludingNoteID, noteID == excludingNoteID {
                searchStart = closeRange.upperBound
                continue
            }

            if !seen.contains(noteID) {
                seen.insert(noteID)
                results.append((noteID, title))
            }

            searchStart = closeRange.upperBound
        }

        return results
    }

    /// Removes every `[[notelink|<uuid>|<title>]]` whose target UUID is in `removedTargetIDs`.
    /// Parsing mirrors `outgoingNotelinks` (including `maxSplits: 1` for titles containing `|`).
    /// Malformed tokens or unknown UUIDs are left unchanged.
    static func removingNotelinks(targeting removedTargetIDs: Set<UUID>, from content: String) -> String {
        guard !removedTargetIDs.isEmpty, content.contains(openToken) else { return content }

        var result = ""
        result.reserveCapacity(content.count)
        var scanStart = content.startIndex

        while let openRange = content.range(of: openToken, range: scanStart..<content.endIndex) {
            result.append(contentsOf: content[scanStart..<openRange.lowerBound])
            let afterOpen = openRange.upperBound
            guard let closeRange = content[afterOpen...].range(of: "]]") else {
                // Unclosed token: keep the rest of the string verbatim (do not drop tail).
                result.append(contentsOf: content[openRange.lowerBound...])
                return result
            }

            let body = String(content[afterOpen..<closeRange.lowerBound])
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let shouldStrip: Bool
            if parts.count == 2,
                let noteID = UUID(uuidString: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines))
            {
                shouldStrip = removedTargetIDs.contains(noteID)
            } else {
                shouldStrip = false
            }

            if !shouldStrip {
                result.append(contentsOf: content[openRange.lowerBound..<closeRange.upperBound])
            }
            scanStart = closeRange.upperBound
        }

        result.append(contentsOf: content[scanStart...])
        return result
    }
}
