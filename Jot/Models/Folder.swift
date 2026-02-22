//
//  Folder.swift
//  Jot
//

import Foundation

struct Folder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String?
    var isArchived: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String? = nil, isArchived: Bool = false, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
