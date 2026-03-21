import Foundation
import SwiftData

@Model
final class NoteVersionEntity {
    var id: UUID
    var noteID: UUID
    var title: String
    var content: String
    var createdAt: Date

    init(noteID: UUID, title: String, content: String) {
        self.id = UUID()
        self.noteID = noteID
        self.title = title
        self.content = content
        self.createdAt = Date()
    }
}

struct NoteVersion: Identifiable {
    let id: UUID
    let noteID: UUID
    let title: String
    let content: String
    let createdAt: Date
}
