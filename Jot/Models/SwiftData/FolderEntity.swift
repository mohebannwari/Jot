import Foundation
import SwiftData

@Model
final class FolderEntity {
    var id: UUID
    var name: String
    var colorHex: String?
    var isArchived: Bool = false
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, colorHex: String? = nil, isArchived: Bool = false, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    convenience init(from folder: Folder) {
        self.init(name: folder.name, colorHex: folder.colorHex, isArchived: folder.isArchived, createdAt: folder.createdAt, modifiedAt: folder.modifiedAt)
        self.id = folder.id
    }

    func rename(to newName: String) {
        self.name = newName
        self.modifiedAt = Date()
    }

    func update(name: String, colorHex: String?) {
        self.name = name
        self.colorHex = colorHex
        self.modifiedAt = Date()
    }

    func toFolder() -> Folder {
        Folder(id: id, name: name, colorHex: colorHex, isArchived: isArchived, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}
