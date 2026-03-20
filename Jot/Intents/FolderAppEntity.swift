//
//  FolderAppEntity.swift
//  Jot
//

import AppIntents

struct FolderAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Folder"
    static var defaultQuery = FolderQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(from folder: Folder) {
        self.id = folder.id
        self.name = folder.name
    }
}

struct FolderQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [FolderAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        return await manager.folders
            .filter { identifiers.contains($0.id) }
            .map { FolderAppEntity(from: $0) }
    }

    func entities(matching string: String) async throws -> [FolderAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        return await manager.folders
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { FolderAppEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [FolderAppEntity] {
        guard let manager = await SimpleSwiftDataManager.shared else { return [] }
        return await manager.folders.map { FolderAppEntity(from: $0) }
    }
}
