//
//  CreateNoteIntent.swift
//  Jot
//

import AppIntents

struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Create a new note in Jot.")

    @Parameter(title: "Title")
    var noteTitle: String

    @Parameter(title: "Content", default: "")
    var content: String

    @Parameter(title: "Folder", optionsProvider: FolderOptionsProvider())
    var folder: FolderAppEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteAppEntity> {
        let manager = try await awaitManager()
        let note = manager.addNote(
            title: noteTitle,
            content: content,
            folderID: folder?.id
        )
        return .result(value: NoteAppEntity(from: note))
    }
}

private struct FolderOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [FolderAppEntity] {
        guard let manager = SimpleSwiftDataManager.shared else { return [] }
        return manager.folders.map { FolderAppEntity(from: $0) }
    }
}
