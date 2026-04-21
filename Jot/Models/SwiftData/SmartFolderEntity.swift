//
//  SmartFolderEntity.swift
//  Jot
//

import Foundation
import SwiftData

@Model
final class SmartFolderEntity {
    var id: UUID
    var name: String
    var predicateData: Data
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, predicate: SmartFolderPredicate, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.predicateData = (try? SmartFolderEntity.encodePredicate(predicate)) ?? Data()
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    convenience init(from smartFolder: SmartFolder) {
        self.init(name: smartFolder.name, predicate: smartFolder.predicate, createdAt: smartFolder.createdAt, modifiedAt: smartFolder.modifiedAt)
        self.id = smartFolder.id
        self.predicateData = (try? Self.encodePredicate(smartFolder.predicate)) ?? Data()
    }

    func toSmartFolder() -> SmartFolder {
        let predicate = (try? Self.decodePredicate(predicateData)) ?? SmartFolderPredicate()
        return SmartFolder(id: id, name: name, predicate: predicate, createdAt: createdAt, modifiedAt: modifiedAt)
    }

    func update(name: String, predicate: SmartFolderPredicate) {
        self.name = name
        self.predicateData = (try? Self.encodePredicate(predicate)) ?? Data()
        self.modifiedAt = Date()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func encodePredicate(_ p: SmartFolderPredicate) throws -> Data {
        try encoder.encode(p)
    }

    static func decodePredicate(_ data: Data) throws -> SmartFolderPredicate {
        try decoder.decode(SmartFolderPredicate.self, from: data)
    }
}
