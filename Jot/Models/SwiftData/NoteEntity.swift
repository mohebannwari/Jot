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
    var isPinned: Bool = false
    var isArchived: Bool = false
    var isLocked: Bool = false
    var isDeleted: Bool = false
    var deletedDate: Date?
    var folderID: UUID?

    // MARK: - Computed Properties for Search
    @Transient
    var searchableContent: String {
        "\(title) \(content)".lowercased()
    }

    @Transient
    var displayDate: String {
        Self.displayDateFormatter.string(from: modifiedAt)
    }

    // MARK: - Performance Optimized Properties
    @Transient
    var contentPreview: String {
        let stripped = Self.contentStripRegex.stringByReplacingMatches(
            in: content, range: NSRange(content.startIndex..., in: content), withTemplate: "")
        return stripped.count <= 150 ? stripped : String(stripped.prefix(150)) + "..."
    }

    // MARK: - Sticker Storage
    var stickersData: Data?

    // MARK: - Meeting Notes
    var isMeetingNote: Bool = false
    var meetingSessionsData: Data?
    // Legacy flat fields — kept for backward-compat migration
    var meetingTranscript: String = ""
    var meetingSummary: String = ""
    var meetingDuration: Double = 0
    var meetingLanguage: String = ""
    var meetingManualNotes: String = ""

    // MARK: - Tags
    var tags: [String] = []
    /// Suggested by on-device model; not mixed into `tags`.
    var aiGeneratedTags: [String] = []

    // MARK: - Web Clip Support
    var webClipURL: String?
    var webClipTitle: String?
    var webClipDescription: String?

    @Transient
    var isWebClip: Bool {
        webClipURL != nil
    }

    // MARK: - Shared Formatters
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Shared Static Resources
    private static let contentStripRegex = try! NSRegularExpression(pattern: #"\[\[/?[^\]]*\]\]"#)
    private static let webClipRegex = try! NSRegularExpression(
        pattern: #"\[\[webclip\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#
    )
    private static let decoder = JSONDecoder()

    // MARK: - Initialization
    init(
        title: String,
        content: String,
        createdAt: Date,
        modifiedAt: Date,
        isPinned: Bool = false,
        isArchived: Bool = false,
        isLocked: Bool = false,
        isDeleted: Bool = false,
        deletedDate: Date? = nil,
        folderID: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isLocked = isLocked
        self.isDeleted = isDeleted
        self.deletedDate = deletedDate
        self.folderID = folderID
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
            modifiedAt: note.date,
            isPinned: note.isPinned,
            isArchived: note.isArchived,
            isLocked: note.isLocked,
            isDeleted: note.isDeleted,
            deletedDate: note.deletedDate,
            folderID: note.folderID
        )
        self.id = note.id
        if !note.stickers.isEmpty {
            self.stickersData = try? JSONEncoder().encode(note.stickers)
        }

        // Meeting notes — encoding failure must not silently erase sessions
        self.isMeetingNote = note.isMeetingNote
        if !note.meetingSessions.isEmpty {
            self.meetingSessionsData = (try? JSONEncoder().encode(note.meetingSessions)) ?? self.meetingSessionsData
            self.meetingTranscript = ""
            self.meetingSummary = ""
            self.meetingDuration = 0
            self.meetingLanguage = ""
            self.meetingManualNotes = ""
        } else {
            self.meetingSessionsData = nil
            self.meetingTranscript = note.meetingTranscript
            self.meetingSummary = note.meetingSummary
            self.meetingDuration = note.meetingDuration
            self.meetingLanguage = note.meetingLanguage
            self.meetingManualNotes = note.meetingManualNotes
        }
        self.tags = note.tags
        self.aiGeneratedTags = note.aiGeneratedTags
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

    /// Syncs `webClipURL/Title/Description` with the `[[webclip|title|desc|url]]` marker in `content`.
    /// If the marker was removed from the note (user deleted it), the fields are cleared so the
    /// entity stops reporting `isWebClip == true` forever. Called on `updateContent` and on
    /// `init(from:)` — safe to run repeatedly because it's idempotent on unchanged content.
    private func extractWebClipData() {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = Self.webClipRegex.firstMatch(in: content, range: range),
              match.numberOfRanges >= 4,
              let titleSubstring = Range(match.range(at: 1), in: content),
              let descSubstring = Range(match.range(at: 2), in: content),
              let urlSubstring = Range(match.range(at: 3), in: content)
        else {
            // No marker found — clear any previously-extracted web clip fields so the note
            // no longer reports as a web clip. This fixes a bug where deleting the marker
            // left `isWebClip == true` forever because extractWebClipData only wrote fields
            // on match, never cleared them on miss.
            self.webClipTitle = nil
            self.webClipDescription = nil
            self.webClipURL = nil
            return
        }

        self.webClipTitle = String(content[titleSubstring])
        self.webClipDescription = String(content[descSubstring])
        self.webClipURL = String(content[urlSubstring])
    }

    // MARK: - Update Methods
    func updateContent(_ newContent: String) {
        // Skip regex scan when content is unchanged — saves work on autosave flush cycles
        // that write identical content (e.g. title-only edits that round-trip through updateContent).
        let contentChanged = newContent != self.content
        self.content = newContent
        self.modifiedAt = Date()
        if contentChanged {
            self.extractWebClipData()
        }
    }

    func updateTitle(_ newTitle: String) {
        self.title = newTitle
        self.modifiedAt = Date()
    }

    // MARK: - Export/Conversion
    func toNote() -> Note {
        var note = Note(title: title, content: content, tags: tags, isPinned: isPinned, folderID: folderID, isArchived: isArchived, isLocked: isLocked, isDeleted: isDeleted, deletedDate: deletedDate, isMeetingNote: isMeetingNote)
        note.id = id
        note.date = modifiedAt
        note.createdAt = createdAt
        if let data = stickersData {
            note.stickers = (try? Self.decoder.decode([Sticker].self, from: data)) ?? []
        }
        // Decode sessions, or migrate from legacy flat fields
        if let data = meetingSessionsData,
           let sessions = try? Self.decoder.decode([MeetingSession].self, from: data) {
            note.meetingSessions = sessions
        } else if isMeetingNote && (!meetingSummary.isEmpty || !meetingTranscript.isEmpty || meetingDuration > 0) {
            // Legacy migration: synthesize a single session from flat fields
            note.meetingSessions = [MeetingSession(
                date: modifiedAt,
                summary: meetingSummary,
                transcript: meetingTranscript,
                duration: meetingDuration,
                language: meetingLanguage,
                manualNotes: meetingManualNotes
            )]
        }
        note.aiGeneratedTags = aiGeneratedTags
        return note
    }
}

// MARK: - Search Extensions
extension NoteEntity {
    static func searchPredicate(for query: String) -> Predicate<NoteEntity> {
        let searchTerms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let firstTerm = searchTerms.first else {
            return #Predicate<NoteEntity> { _ in false }
        }

        // Tags are merged in `SimpleSwiftDataManager.searchNotes` from the in-memory note list.
        // SwiftData cannot express "any tag contains substring" on `[String]` here without crashing
        // the Core Data SQL generator (non-relationship collection subquery).
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
        return [
            SortDescriptor(\.modifiedAt, order: .reverse),
            SortDescriptor(\.createdAt, order: .reverse)
        ]
    }
}
