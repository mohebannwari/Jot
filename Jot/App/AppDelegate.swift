import Cocoa
import CoreSpotlight

/// Handles macOS application lifecycle events that SwiftUI's App protocol doesn't cover,
/// specifically Spotlight deep linking via NSUserActivity.
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let noteIDString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let noteID = UUID(uuidString: noteIDString) else {
            return false
        }

        NotificationCenter.default.post(.openNoteFromSpotlight(noteID: noteID))
        return true
    }
}
