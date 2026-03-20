//
//  NoteAppEntity.swift
//  Jot
//

import AppIntents

struct NoteAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static var defaultQuery = NoteQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(from note: Note) {
        self.id = note.id
        self.title = note.title.isEmpty ? "Untitled" : note.title
    }
}

struct NoteQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [NoteAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        return await manager.notes
            .filter { identifiers.contains($0.id) }
            .map { NoteAppEntity(from: $0) }
    }

    func entities(matching string: String) async throws -> [NoteAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        let results = await manager.searchNotes(query: string, limit: 20)
        return results.map { NoteAppEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [NoteAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        return await Array(manager.notes.prefix(10)).map { NoteAppEntity(from: $0) }
    }
}
