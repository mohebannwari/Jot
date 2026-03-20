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
    private var exportService: NoteExportService { NoteExportService.shared }
    /// Max characters for Spotlight content preview
    private let contentPreviewLimit = 300

    private init() {}

    /// Index a single note. Automatically deindexes if the note is deleted or archived.
    func indexNote(_ note: Note) {
        if note.isDeleted || note.isArchived {
            deindexNotes(ids: [note.id])
            return
        }

        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = note.title.isEmpty ? "Untitled" : note.title

        // Locked notes: title only, no content exposed to Spotlight
        if !note.isLocked {
            let plainText = exportService.convertMarkupToPlainText(note.content)
            attrs.contentDescription = String(plainText.prefix(contentPreviewLimit))
        }

        attrs.keywords = note.tags
        attrs.lastUsedDate = note.date
        attrs.contentCreationDate = note.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attrs
        )

        index.indexSearchableItems([item]) { error in
            if let error {
                NSLog("SpotlightIndexer: Failed to index note: %@", error.localizedDescription)
            }
        }
    }

    /// Remove notes from the Spotlight index.
    func deindexNotes(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        index.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString)) { error in
            if let error {
                NSLog("SpotlightIndexer: Failed to deindex notes: %@", error.localizedDescription)
            }
        }
    }

    /// Full reindex of all active notes. Called on app launch.
    func reindexAll(_ notes: [Note]) {
        let items: [CSSearchableItem] = notes
            .filter { !$0.isDeleted && !$0.isArchived }
            .map { note in
                let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
                attrs.title = note.title.isEmpty ? "Untitled" : note.title
                if !note.isLocked {
                    let plainText = exportService.convertMarkupToPlainText(note.content)
                    attrs.contentDescription = String(plainText.prefix(contentPreviewLimit))
                }
                attrs.keywords = note.tags
                attrs.lastUsedDate = note.date
                attrs.contentCreationDate = note.createdAt
                return CSSearchableItem(
                    uniqueIdentifier: note.id.uuidString,
                    domainIdentifier: domainID,
                    attributeSet: attrs
                )
            }

        // Replace entire index to stay in sync
        let idx = index
        idx.deleteAllSearchableItems { error in
            if let error {
                NSLog("SpotlightIndexer: Failed to clear index: %@", error.localizedDescription)
            }
            idx.indexSearchableItems(items) { error in
                if let error {
                    NSLog("SpotlightIndexer: Failed to reindex all: %@", error.localizedDescription)
                }
            }
        }
    }
}
