//
//  SmartFolder.swift
//  Jot
//

import Foundation

struct SmartFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var predicate: SmartFolderPredicate
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        predicate: SmartFolderPredicate,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.predicate = predicate
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
