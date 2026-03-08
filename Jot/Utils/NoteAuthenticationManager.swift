import Combine
import Foundation
import LocalAuthentication
import OpenDirectory

enum AuthMethod {
    case login
    case custom
    case touchID
}

@MainActor
final class NoteAuthenticationManager: ObservableObject {
    @Published var unlockedNoteIDs: Set<UUID> = []

    /// Pending re-lock timers keyed by note ID.
    private var relockTimers: [UUID: DispatchWorkItem] = [:]

    /// How long an unlocked note stays unlocked after navigating away.
    private let relockDelay: TimeInterval = 5 * 60 // 5 minutes

    func isUnlocked(_ noteID: UUID) -> Bool {
        unlockedNoteIDs.contains(noteID)
    }

    /// Call when the user navigates away from an unlocked, locked note.
    /// Starts a timer that re-locks the note after `relockDelay`.
    func scheduleRelock(for noteID: UUID) {
        guard unlockedNoteIDs.contains(noteID) else { return }
        cancelRelock(for: noteID)

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.unlockedNoteIDs.remove(noteID)
                self?.relockTimers.removeValue(forKey: noteID)
            }
        }
        relockTimers[noteID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + relockDelay, execute: work)
    }

    /// Call when the user returns to an unlocked note — cancels the pending re-lock.
    func cancelRelock(for noteID: UUID) {
        relockTimers[noteID]?.cancel()
        relockTimers.removeValue(forKey: noteID)
    }

    func authenticate(noteID: UUID, method: AuthMethod, customPasswordInput: String = "", completion: @escaping (Bool) -> Void) {
        switch method {
        case .login:
            authenticateWithLoginPassword(noteID: noteID, password: customPasswordInput, completion: completion)
        case .custom:
            authenticateWithCustomPassword(noteID: noteID, input: customPasswordInput, completion: completion)
        case .touchID:
            authenticateWithBiometrics(noteID: noteID, completion: completion)
        }
    }

    private func authenticateWithLoginPassword(noteID: UUID, password: String, completion: @escaping (Bool) -> Void) {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let query = try ODQuery(
                node: node,
                forRecordTypes: kODRecordTypeUsers,
                attribute: kODAttributeTypeRecordName,
                matchType: ODMatchType(kODMatchEqualTo),
                queryValues: NSUserName(),
                returnAttributes: kODAttributeTypeNativeOnly,
                maximumResults: 1
            )
            let results = try query.resultsAllowingPartial(false)
            guard let record = results.first as? ODRecord else {
                completion(false)
                return
            }
            try record.verifyPassword(password)
            unlockedNoteIDs.insert(noteID)
            completion(true)
        } catch {
            completion(false)
        }
    }

    private func authenticateWithCustomPassword(noteID: UUID, input: String, completion: @escaping (Bool) -> Void) {
        guard let stored = KeychainManager.loadPassword(), stored == input else {
            completion(false)
            return
        }
        unlockedNoteIDs.insert(noteID)
        completion(true)
    }

    private func authenticateWithBiometrics(noteID: UUID, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock note with Touch ID") { [weak self] success, _ in
            Task { @MainActor in
                if success {
                    self?.unlockedNoteIDs.insert(noteID)
                }
                completion(success)
            }
        }
    }
}
