//
//  Note.swift
//  Noty
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

    init(title: String, content: String, tags: [String] = [], isPinned: Bool = false) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.date = Date()
        self.tags = tags
        self.isPinned = isPinned
    }
}
