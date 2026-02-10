//
//  NoteDragItem.swift
//  Jot
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct NoteDragItem: Codable, Hashable, Transferable {
    let noteID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jotNoteDragItem)
    }
}

extension UTType {
    static let jotNoteDragItem = UTType(exportedAs: "com.jot.note-drag-item")
}
