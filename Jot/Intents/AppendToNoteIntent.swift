//
//  AppendToNoteIntent.swift
//  Jot
//

import AppIntents

struct AppendToNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Append to Note"
    static var description = IntentDescription("Append text to an existing note in Jot.")

    @Parameter(title: "Note")
    var note: NoteAppEntity

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = try await awaitManager()

        guard var existingNote = manager.notes.first(where: { $0.id == note.id }) else {
            throw IntentError.noteNotFound
        }
        guard existingNote.isAvailableToAppIntents else {
            throw IntentError.noteLocked
        }

        let separator = existingNote.content.isEmpty ? "" : "\n"
        existingNote.content += separator + text
        manager.updateNote(existingNote)

        return .result()
    }
}
