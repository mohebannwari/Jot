//
//  OpenNoteIntent.swift
//  Jot
//

import AppIntents

struct OpenNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Note"
    static var description = IntentDescription("Open an existing note in Jot.")
    static var openAppWhenRun = true

    @Parameter(title: "Note")
    var note: NoteAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await awaitManager()
        NotificationCenter.default.post(.openNoteFromSpotlight(noteID: note.id))
        return .result()
    }
}
