import Foundation
import SwiftData

@Model
final class FolderEntity {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    convenience init(from folder: Folder) {
        self.init(name: folder.name, createdAt: folder.createdAt, modifiedAt: folder.modifiedAt)
        self.id = folder.id
    }

    func rename(to newName: String) {
        self.name = newName
        self.modifiedAt = Date()
    }

    func toFolder() -> Folder {
        Folder(id: id, name: name, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}
