//
//  QuickNoteService.swift
//  Jot
//
//  Single save path for quick-captured notes. Resolves or creates the
//  "Quick Notes" inbox folder, then delegates to SimpleSwiftDataManager.addNote.
//  Folder identity is tracked by UUID stored in UserDefaults so renames are
//  honored and deletions trigger transparent recreation on the next save.
//

import Foundation
import os

@MainActor
final class QuickNoteService {

    /// Lazily resolved so that construction happens after `JotApp.init` has
    /// assigned `SimpleSwiftDataManager.shared`. The static property crashes
    /// loudly if the manager hasn't been initialized yet — by design.
    static let shared: QuickNoteService = {
        guard let manager = SimpleSwiftDataManager.shared else {
            fatalError("QuickNoteService.shared accessed before SimpleSwiftDataManager.shared was initialized")
        }
        return QuickNoteService(manager: manager, defaults: .standard)
    }()

    private let manager: SimpleSwiftDataManager
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.jot", category: "QuickNoteService")

    private static let inboxFolderName = "Quick Notes"
    private static let titleTruncationLimit = 60
    private static let fallbackTitle = "Quick Note"

    init(manager: SimpleSwiftDataManager, defaults: UserDefaults) {
        self.manager = manager
        self.defaults = defaults
    }

    // MARK: - Save

    @discardableResult
    func save(title: String, body: String) -> Note {
        let folderID = resolveOrCreateInboxFolder()
        let effectiveTitle = derivedTitle(rawTitle: title, body: body)
        logger.info("Saving quick note: \(effectiveTitle)")
        return manager.addNote(
            title: effectiveTitle,
            content: body,
            folderID: folderID
        )
    }

    // MARK: - Folder resolution

    /// Returns the UUID of the Quick Notes inbox folder, creating it if the
    /// stored ID is nil or points to a folder that no longer exists.
    /// - Returns: the folder UUID, or nil only if folder creation itself fails.
    private func resolveOrCreateInboxFolder() -> UUID? {
        if let idString = defaults.string(forKey: ThemeManager.quickNotesFolderIDKey),
           let id = UUID(uuidString: idString),
           manager.folders.contains(where: { $0.id == id }) {
            return id
        }

        guard let folder = manager.createFolder(name: Self.inboxFolderName) else {
            logger.error("Failed to create Quick Notes inbox folder")
            return nil
        }
        defaults.set(folder.id.uuidString, forKey: ThemeManager.quickNotesFolderIDKey)
        return folder.id
    }

    // MARK: - Title derivation

    private func derivedTitle(rawTitle: String, body: String) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        // First non-empty line of body, trimmed, then truncated to the display limit.
        let firstLine = body
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })

        if let line = firstLine, !line.isEmpty {
            if line.count <= Self.titleTruncationLimit {
                return line
            }
            return String(line.prefix(Self.titleTruncationLimit))
        }

        return Self.fallbackTitle
    }
}
