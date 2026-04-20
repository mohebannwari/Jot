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
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NoteAppEntity] {
        guard let manager = SimpleSwiftDataManager.shared else { return [] }
        let identifierSet = Set(identifiers)
        return manager.notes
            .filter { identifierSet.contains($0.id) && $0.isAvailableToAppIntents }
            .map { NoteAppEntity(from: $0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteAppEntity] {
        guard let manager = SimpleSwiftDataManager.shared else { return [] }
        let results = await manager.searchNotes(query: string, limit: 20)
        return results
            .filter(\.isAvailableToAppIntents)
            .map { NoteAppEntity(from: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteAppEntity] {
        guard let manager = SimpleSwiftDataManager.shared else { return [] }
        return manager.notes
            .filter(\.isAvailableToAppIntents)
            .prefix(10)
            .map { NoteAppEntity(from: $0) }
    }
}
