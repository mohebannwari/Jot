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
    var createdAt: Date = Date()
    var tags: [String]
    var isPinned: Bool = false
    var folderID: UUID?
    var isArchived: Bool = false
    var isLocked: Bool = false
    var isDeleted: Bool = false
    var deletedDate: Date?
    var stickers: [Sticker] = []

    // Meeting Notes
    var isMeetingNote: Bool = false
    var meetingTranscript: String = ""
    var meetingSummary: String = ""
    var meetingDuration: TimeInterval = 0
    var meetingLanguage: String = ""
    var meetingManualNotes: String = ""

    init(
        title: String,
        content: String,
        tags: [String] = [],
        isPinned: Bool = false,
        folderID: UUID? = nil,
        isArchived: Bool = false,
        isLocked: Bool = false,
        isDeleted: Bool = false,
        deletedDate: Date? = nil,
        isMeetingNote: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = Date()
        self.tags = tags
        self.isPinned = isPinned
        self.folderID = folderID
        self.isArchived = isArchived
        self.isLocked = isLocked
        self.isDeleted = isDeleted
        self.deletedDate = deletedDate
        self.isMeetingNote = isMeetingNote
    }
}
