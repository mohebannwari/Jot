//
//  Note.swift
//  Jot
//
//  Created by Moheb Anwari on 05.08.25.
//

import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var content: String
    var date: Date
    var tags: [String]
    var isPinned: Bool = false
    var folderID: UUID?
    var isArchived: Bool = false
    var isDeleted: Bool = false
    var deletedDate: Date?

    init(
        title: String,
        content: String,
        tags: [String] = [],
        isPinned: Bool = false,
        folderID: UUID? = nil,
        isArchived: Bool = false,
        isDeleted: Bool = false,
        deletedDate: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = Date()
        self.tags = tags
        self.isPinned = isPinned
        self.folderID = folderID
        self.isArchived = isArchived
        self.isDeleted = isDeleted
        self.deletedDate = deletedDate
    }
}
