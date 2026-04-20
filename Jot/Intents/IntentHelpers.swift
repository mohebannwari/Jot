//
//  IntentHelpers.swift
//  Jot
//

import Foundation

enum IntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case managerUnavailable
    case noteNotFound
    case noteLocked

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .managerUnavailable:
            return "Jot is still loading. Please try again in a moment."
        case .noteNotFound:
            return "The note could not be found. It may have been deleted."
        case .noteLocked:
            return "That note is locked. Unlock it in Jot before using this shortcut."
        }
    }
}

extension Note {
    var isAvailableToAppIntents: Bool {
        !isLocked
    }
}

/// Waits for SimpleSwiftDataManager.shared to become available (up to 5 seconds).
/// Use this in App Intents to handle the case where the app is still launching.
@MainActor
func awaitManager() async throws -> SimpleSwiftDataManager {
    for _ in 0..<50 {
        if let manager = SimpleSwiftDataManager.shared {
            return manager
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw IntentError.managerUnavailable
}
