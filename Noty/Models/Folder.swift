//
//  Folder.swift
//  Noty
//

import Foundation

struct Folder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String?
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String? = nil, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
