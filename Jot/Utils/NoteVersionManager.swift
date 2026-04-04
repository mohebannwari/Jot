import Foundation
import SwiftData
import OSLog

/// Manages per-note version snapshots with debounced creation and deduplication.
/// Snapshots are triggered from SimpleSwiftDataManager.updateNote() and flushed on note switch.
@MainActor
final class NoteVersionManager {
    static let shared = NoteVersionManager()

    private let logger = Logger(subsystem: "com.jot.app", category: "NoteVersionManager")
    private let snapshotDebounceInterval: TimeInterval = 30
    private let maxVersionsPerNote = 50

    /// Pending debounced snapshot tasks keyed by noteID
    private var pendingSnapshots: [UUID: Task<Void, Never>] = [:]
    /// Tracks the content hash of the last pending schedule to avoid re-scheduling for identical content
    private var lastScheduledContentHash: [UUID: Int] = [:]

    private init() {}

    // MARK: - Public API

    /// Schedules a debounced snapshot for the given note. Called after every updateNote().
    /// If a snapshot is already pending for this note, the timer resets.
    func scheduleSnapshot(for note: Note, in context: ModelContext) {
        let noteID = note.id
        let title = note.title
        let content = note.content

        // Skip if content hasn't changed since last schedule
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(content)
        let contentHash = hasher.finalize()
        if lastScheduledContentHash[noteID] == contentHash {
            return
        }
        lastScheduledContentHash[noteID] = contentHash

        // Cancel existing pending snapshot for this note
        pendingSnapshots[noteID]?.cancel()

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.snapshotDebounceInterval ?? 30))
            guard !Task.isCancelled else { return }
            self?.takeSnapshot(noteID: noteID, title: title, content: content, in: context)
            self?.pendingSnapshots.removeValue(forKey: noteID)
        }

        pendingSnapshots[noteID] = task
    }

    /// Immediately fires any pending snapshot for the given note (e.g., on note switch).
    func flushPendingSnapshot(for noteID: UUID, in context: ModelContext) {
        guard let task = pendingSnapshots.removeValue(forKey: noteID) else { return }
        task.cancel()
        lastScheduledContentHash.removeValue(forKey: noteID)

        // Fetch the current note content to snapshot
        let id = noteID
        let predicate = #Predicate<NoteEntity> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let entity = try? context.fetch(descriptor).first else {
            logger.warning("Cannot flush snapshot: note \(noteID) not found")
            return
        }

        takeSnapshot(noteID: noteID, title: entity.title, content: entity.content, in: context)
    }

    /// Immediately creates a version snapshot without debouncing.
    /// Used for pre-restore safety snapshots where a 30s delay would be useless.
    func forceSnapshot(for note: Note, in context: ModelContext) {
        lastScheduledContentHash.removeValue(forKey: note.id)
        pendingSnapshots[note.id]?.cancel()
        pendingSnapshots.removeValue(forKey: note.id)
        takeSnapshot(noteID: note.id, title: note.title, content: note.content, in: context)
    }

    /// Fetches all versions for a note, sorted newest first.
    func versions(for noteID: UUID, in context: ModelContext) -> [NoteVersion] {
        let id = noteID
        let predicate = #Predicate<NoteVersionEntity> { $0.noteID == id }
        var descriptor = FetchDescriptor<NoteVersionEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        do {
            return try context.fetch(descriptor).map { entity in
                NoteVersion(
                    id: entity.id,
                    noteID: entity.noteID,
                    title: entity.title,
                    content: entity.content,
                    createdAt: entity.createdAt
                )
            }
        } catch {
            logger.error("Failed to fetch versions for note \(noteID): \(error)")
            return []
        }
    }

    /// Deletes versions older than the retention period. Called on app launch.
    func pruneVersions(retentionDays: Int, in context: ModelContext) {
        guard retentionDays > 0 else { return } // 0 = keep forever

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let predicate = #Predicate<NoteVersionEntity> { $0.createdAt < cutoff }
        let descriptor = FetchDescriptor<NoteVersionEntity>(predicate: predicate)

        do {
            let expired = try context.fetch(descriptor)
            guard !expired.isEmpty else { return }
            for entity in expired {
                context.delete(entity)
            }
            try context.save()
            logger.info("Pruned \(expired.count) expired version snapshots")
        } catch {
            logger.error("Failed to prune versions: \(error)")
        }
    }

    // MARK: - Private

    private func takeSnapshot(noteID: UUID, title: String, content: String, in context: ModelContext) {
        // Skip if duplicate of the most recent version
        if isDuplicateOfLast(content: content, title: title, noteID: noteID, in: context) {
            logger.info("Skipping duplicate snapshot for note \(noteID)")
            return
        }

        let version = NoteVersionEntity(noteID: noteID, title: title, content: content)
        context.insert(version)

        do {
            try context.save()
            logger.info("Created version snapshot for note \(noteID)")
        } catch {
            logger.error("Failed to save version snapshot: \(error)")
            return
        }

        enforceVersionCap(for: noteID, limit: maxVersionsPerNote, in: context)
    }

    private func enforceVersionCap(for noteID: UUID, limit: Int, in context: ModelContext) {
        let id = noteID
        let predicate = #Predicate<NoteVersionEntity> { $0.noteID == id }
        var descriptor = FetchDescriptor<NoteVersionEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Fetch only the excess rows beyond the cap, not all versions
        descriptor.fetchOffset = limit

        do {
            let excess = try context.fetch(descriptor)
            guard !excess.isEmpty else { return }
            for entity in excess {
                context.delete(entity)
            }
            try context.save()
            logger.info("Enforced version cap: deleted \(excess.count) oldest snapshots for note \(noteID)")
        } catch {
            logger.error("Failed to enforce version cap for note \(noteID): \(error)")
        }
    }

    private func isDuplicateOfLast(content: String, title: String, noteID: UUID, in context: ModelContext) -> Bool {
        let id = noteID
        let predicate = #Predicate<NoteVersionEntity> { $0.noteID == id }
        var descriptor = FetchDescriptor<NoteVersionEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let latest = try? context.fetch(descriptor).first else {
            return false
        }

        return latest.title == title && latest.content == content
    }
}
