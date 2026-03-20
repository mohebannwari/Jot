//
//  SearchNotesIntent.swift
//  Jot
//

import AppIntents

struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes"
    static var description = IntentDescription("Search for notes in Jot by keyword.")

    @Parameter(title: "Query")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[NoteAppEntity]> {
        let manager = try await awaitManager()
        let results = await manager.searchNotes(query: query, limit: 20)
        return .result(value: results.map { NoteAppEntity(from: $0) })
    }
}
