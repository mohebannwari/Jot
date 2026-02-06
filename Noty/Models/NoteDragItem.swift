//
//  NoteDragItem.swift
//  Noty
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct NoteDragItem: Codable, Hashable, Transferable {
    let noteID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .notyNoteDragItem)
    }
}

extension UTType {
    static let notyNoteDragItem = UTType(exportedAs: "com.noty.note-drag-item")
}
