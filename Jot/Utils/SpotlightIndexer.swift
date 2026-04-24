@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes Jot notes in macOS Spotlight so they appear in system-wide search.
/// Locked notes are indexed by title only (no content exposed).
/// Deleted and archived notes are removed from the index.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private let domainID = "com.jot.notes"
    private let contentPreviewLimit = 300
    var onIndexNoteForTesting: ((Note) -> Void)?

    private init() {}

    /// Merges user and AI-suggested tags for indexing (case-insensitive unique, preserves first spelling).
    private static func mergedSpotlightKeywords(for note: Note) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in note.tags + note.aiGeneratedTags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let low = t.lowercased()
            if seen.contains(low) { continue }
            seen.insert(low)
            out.append(t)
        }
        return out
    }

    /// Builds a searchable item from a note. Extracted for testability and DRY.
    func buildSearchableItem(for note: Note) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = note.title.isEmpty ? "Untitled" : note.title

        // Locked notes: title only, no content exposed to Spotlight
        if !note.isLocked {
            let plainText = NoteExportService.shared.convertMarkupToPlainText(note.content)
            attrs.contentDescription = String(plainText.prefix(contentPreviewLimit))
        }

        attrs.keywords = Self.mergedSpotlightKeywords(for: note)
        attrs.lastUsedDate = note.date
        attrs.contentCreationDate = note.createdAt

        return CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attrs
        )
    }

    /// Index a single note. Automatically deindexes if the note is deleted or archived.
    func indexNote(_ note: Note) {
        if note.isDeleted || note.isArchived {
            deindexNotes(ids: [note.id])
            return
        }

        onIndexNoteForTesting?(note)
        let item = buildSearchableItem(for: note)
        index.indexSearchableItems([item])
    }

    /// Remove notes from the Spotlight index.
    func deindexNotes(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        index.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    /// Full reindex of all active notes. Runs on a background thread to avoid
    /// blocking the UI on launch. CoreSpotlight upserts by uniqueIdentifier,
    /// so we don't need to delete-then-reindex (no race condition window).
    /// Full reindex of all active notes. Prepares content on the main actor
    /// (where NoteExportService lives), then indexes on a background thread.
    func reindexAll(_ notes: [Note]) {
        // Build items on the main actor (NoteExportService is @MainActor)
        let items: [CSSearchableItem] = notes
            .filter { !$0.isDeleted && !$0.isArchived }
            .map { buildSearchableItem(for: $0) }

        // Index on background using the completion-handler API (async overload).
        Task.detached(priority: .utility) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                CSSearchableIndex.default().indexSearchableItems(items) { _ in
                    cont.resume()
                }
            }
        }
    }
}
