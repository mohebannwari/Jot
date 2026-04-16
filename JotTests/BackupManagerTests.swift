import XCTest
@testable import Jot

/// Tests the restore-flag + flush-broadcast contract of `BackupManager.prepareRestore`.
///
/// `restoreBackup(_:)` itself calls `NSApp.terminate(nil)` which is not safely
/// unit-testable. `prepareRestore(backupPath:userDefaults:notificationCenter:)` is
/// the side-effect-only seam: writes the restore flag to UserDefaults and broadcasts
/// a flush notification so any in-flight editor serialization lands before termination.
@MainActor
final class BackupManagerTests: XCTestCase {

    /// Must write `backupPath` under the "pendingRestoreBackupPath" key so the next
    /// launch's `checkAndPerformPendingRestore` finds the backup to restore from.
    func testPrepareRestore_WritesPendingRestorePath() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let path = "/tmp/backup-\(UUID().uuidString)"

        BackupManager.prepareRestore(
            backupPath: path,
            userDefaults: defaults,
            notificationCenter: NotificationCenter())

        XCTAssertEqual(defaults.string(forKey: "pendingRestoreBackupPath"), path)
    }

    /// Must post `.jotFlushEditorSerializationBeforeTerminate` so every editor
    /// Coordinator flushes pending 150ms-debounced serialization to its binding
    /// BEFORE `NSApp.terminate(nil)` starts killing the process.
    func testPrepareRestore_PostsFlushNotification() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let center = NotificationCenter()
        let expectation = expectation(
            description: "flush notification posted before prepareRestore returns")

        let observer = center.addObserver(
            forName: .jotFlushEditorSerializationBeforeTerminate,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { center.removeObserver(observer) }

        BackupManager.prepareRestore(
            backupPath: "/tmp/irrelevant",
            userDefaults: defaults,
            notificationCenter: center)

        wait(for: [expectation], timeout: 0.1)
    }

    /// Both side effects must happen — flag write MUST NOT be skipped if the flush
    /// notification has no observers (which is the test-only scenario, but also the
    /// real scenario if every editor is torn down before terminate).
    func testPrepareRestore_WritesFlagEvenWithNoFlushObservers() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let path = "/tmp/another-\(UUID().uuidString)"

        BackupManager.prepareRestore(
            backupPath: path,
            userDefaults: defaults,
            notificationCenter: NotificationCenter())

        XCTAssertEqual(defaults.string(forKey: "pendingRestoreBackupPath"), path)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "BackupManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
