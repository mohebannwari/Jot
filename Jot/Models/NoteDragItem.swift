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

// Helper for transferring multiple note drag items
struct TransferablePayload: Codable, Transferable {
    let items: [NoteDragItem]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jotNoteDragPayload)
    }
}

extension UTType {
    static let jotNoteDragPayload = UTType(exportedAs: "com.jot.note-drag-payload")
}
