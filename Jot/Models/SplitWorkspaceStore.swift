import Combine
import CoreGraphics
import Foundation

enum SplitPosition: String, Codable {
    case left
    case right
}

struct SplitSession: Identifiable, Equatable, Codable {
    let id: UUID
    var primaryNoteID: UUID?
    var secondaryNoteID: UUID?
    var position: SplitPosition = .right
    var ratio: CGFloat = 0.5

    init(id: UUID = UUID(), primaryNoteID: UUID? = nil, secondaryNoteID: UUID? = nil) {
        self.id = id
        self.primaryNoteID = primaryNoteID
        self.secondaryNoteID = secondaryNoteID
    }

    var isComplete: Bool { primaryNoteID != nil && secondaryNoteID != nil }
}

@MainActor
final class SplitWorkspaceStore: ObservableObject {
    @Published var sessions: [SplitSession] = []
    @Published var activeID: UUID?
    @Published var pendingID: UUID?
    @Published var isVisible = false

    private static let sessionsKey = "SplitSessionsData"
    private static let activeIDKey = "ActiveSplitID"
    private static let visibleKey = "IsSplitViewVisible"

    var isActive: Bool { !sessions.isEmpty }
    var shouldShowLayout: Bool { activeID != nil && isVisible }
    var isActivePending: Bool { activeID != nil && activeID == pendingID }

    var active: SplitSession? {
        guard let activeID else { return nil }
        return sessions.first(where: { $0.id == activeID })
    }

    var activeIndex: Int? {
        guard let activeID else { return nil }
        return sessions.firstIndex(where: { $0.id == activeID })
    }

    var noteIDs: Set<UUID> {
        var ids = Set<UUID>()
        for session in sessions {
            if let primaryID = session.primaryNoteID { ids.insert(primaryID) }
            if let secondaryID = session.secondaryNoteID { ids.insert(secondaryID) }
        }
        return ids
    }

    func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }

        if let activeID {
            UserDefaults.standard.set(activeID.uuidString, forKey: Self.activeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeIDKey)
        }

        UserDefaults.standard.set(isVisible, forKey: Self.visibleKey)
    }

    func restore(availableNotes notes: [Note], hasLoadedInitialNotes: Bool) -> Note? {
        guard hasLoadedInitialNotes else { return nil }
        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let decodedSessions = try? JSONDecoder().decode([SplitSession].self, from: data)
        else { return nil }

        let availableNoteIDs = Set(notes.map(\.id))
        let validSessions = decodedSessions.filter { session in
            let primaryOK = session.primaryNoteID.map { availableNoteIDs.contains($0) } ?? true
            let secondaryOK = session.secondaryNoteID.map { availableNoteIDs.contains($0) } ?? true
            return primaryOK && secondaryOK && session.isComplete
        }

        guard !validSessions.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.sessionsKey)
            return nil
        }

        sessions = validSessions
        isVisible = UserDefaults.standard.bool(forKey: Self.visibleKey)

        if let idString = UserDefaults.standard.string(forKey: Self.activeIDKey),
           let id = UUID(uuidString: idString),
           validSessions.contains(where: { $0.id == id }) {
            activeID = id
        } else {
            activeID = validSessions.last?.id
        }

        guard let activeSession = validSessions.first(where: { $0.id == activeID }),
              let primaryID = activeSession.primaryNoteID
        else { return nil }

        return notes.first(where: { $0.id == primaryID })
    }

    func activateSession(containing noteID: UUID) -> SplitSession? {
        guard let session = sessions.first(where: {
            $0.primaryNoteID == noteID || $0.secondaryNoteID == noteID
        }) else { return nil }

        activeID = session.id
        isVisible = true
        return session
    }

    func createPendingSplit(position: SplitPosition, primaryNoteID: UUID?) {
        var session = SplitSession()
        session.primaryNoteID = primaryNoteID
        session.position = position
        sessions.append(session)
        activeID = session.id
        pendingID = session.id
        isVisible = true
        save()
    }

    func addPendingSplit() {
        let session = SplitSession()
        sessions.append(session)
        activeID = session.id
        pendingID = session.id
        isVisible = true
        save()
    }

    @discardableResult
    func createOrReplaceActiveSplitFromDrop(
        primaryNoteID: UUID,
        droppedNoteID: UUID,
        position: SplitPosition
    ) -> Bool {
        if let activeIndex {
            sessions[activeIndex].secondaryNoteID = droppedNoteID
            sessions[activeIndex].position = position
            save()
            return false
        }

        var session = SplitSession()
        session.primaryNoteID = primaryNoteID
        session.secondaryNoteID = droppedNoteID
        session.position = position
        sessions.append(session)
        activeID = session.id
        isVisible = true
        save()
        return true
    }

    func completePendingSplitIfNeeded(at index: Int) {
        guard sessions.indices.contains(index), sessions[index].isComplete else { return }
        pendingID = nil
    }

    func cancelPendingSplit() {
        guard let pendingID else { return }
        sessions.removeAll(where: { $0.id == pendingID })
        self.pendingID = nil

        if let lastCompleted = sessions.last(where: { $0.isComplete }) {
            activeID = lastCompleted.id
        } else {
            activeID = nil
            isVisible = false
        }

        save()
    }

    func closeActiveSplit() {
        guard let activeID else { return }
        sessions.removeAll(where: { $0.id == activeID })
        if activeID == pendingID { pendingID = nil }

        if let next = sessions.last(where: { $0.isComplete }) {
            self.activeID = next.id
        } else {
            self.activeID = nil
            isVisible = false
        }

        save()
    }

    func moveActiveToOtherSide() -> UUID? {
        guard let activeIndex else { return nil }
        let oldPrimary = sessions[activeIndex].primaryNoteID
        let oldSecondary = sessions[activeIndex].secondaryNoteID
        sessions[activeIndex].primaryNoteID = oldSecondary
        sessions[activeIndex].secondaryNoteID = oldPrimary
        save()
        return sessions[activeIndex].primaryNoteID
    }

    func clearVisibleSplit() {
        activeID = nil
        isVisible = false
    }
}
