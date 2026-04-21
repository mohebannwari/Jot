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

    override func tearDown() {
        if let manager = try? SimpleSwiftDataManager(inMemoryForTesting: true) {
            BackupManager.performPostInitRestore(
                into: manager,
                userDefaults: UserDefaults.standard,
                fileManager: FileManager.default
            )
        }
        super.tearDown()
    }

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

    func testPendingRestoreDoesNotDeleteStoreWhenNotesFileIsMissing() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backupURL = try makeBackupDirectory(includeNotes: false)
        let storeBaseURL = try makeStoreTriplet()
        defaults.set(backupURL.path, forKey: "pendingRestoreBackupPath")

        let accessURL = BackupManager.checkAndPerformPendingRestore(
            userDefaults: defaults,
            fileManager: .default,
            storeBaseURL: storeBaseURL
        )

        XCTAssertNil(accessURL)
        assertStoreTripletExists(at: storeBaseURL)
        XCTAssertNil(defaults.string(forKey: "pendingImportBackupPath"))
    }

    func testPendingRestoreDoesNotDeleteStoreWhenFoldersFileIsMissing() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backupURL = try makeBackupDirectory(includeFolders: false)
        let storeBaseURL = try makeStoreTriplet()
        defaults.set(backupURL.path, forKey: "pendingRestoreBackupPath")

        let accessURL = BackupManager.checkAndPerformPendingRestore(
            userDefaults: defaults,
            fileManager: .default,
            storeBaseURL: storeBaseURL
        )

        XCTAssertNil(accessURL)
        assertStoreTripletExists(at: storeBaseURL)
        XCTAssertNil(defaults.string(forKey: "pendingImportBackupPath"))
    }

    func testPendingRestoreDoesNotDeleteStoreWhenPayloadIsCorrupt() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backupURL = try makeBackupDirectory(corruptNotes: true)
        let storeBaseURL = try makeStoreTriplet()
        defaults.set(backupURL.path, forKey: "pendingRestoreBackupPath")

        let accessURL = BackupManager.checkAndPerformPendingRestore(
            userDefaults: defaults,
            fileManager: .default,
            storeBaseURL: storeBaseURL
        )

        XCTAssertNil(accessURL)
        assertStoreTripletExists(at: storeBaseURL)
        XCTAssertNil(defaults.string(forKey: "pendingImportBackupPath"))
    }

    func testPendingRestoreDeletesStoreOnlyAfterValidatedPayloadAndImportsData() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedNote = Note(title: "Restored", content: "Body")
        let expectedFolder = Folder(name: "Recovered")
        let backupURL = try makeBackupDirectory(notes: [expectedNote], folders: [expectedFolder])
        let storeBaseURL = try makeStoreTriplet()
        defaults.set(backupURL.path, forKey: "pendingRestoreBackupPath")

        let accessURL = BackupManager.checkAndPerformPendingRestore(
            userDefaults: defaults,
            fileManager: .default,
            storeBaseURL: storeBaseURL
        )

        XCTAssertNil(accessURL)
        assertStoreTripletMissing(at: storeBaseURL)
        XCTAssertEqual(defaults.string(forKey: "pendingImportBackupPath"), backupURL.path)

        let manager = try SimpleSwiftDataManager(inMemoryForTesting: true)
        BackupManager.performPostInitRestore(
            into: manager,
            userDefaults: defaults,
            fileManager: .default
        )

        XCTAssertTrue(manager.notes.contains(where: { $0.id == expectedNote.id }))
        XCTAssertTrue(manager.folders.contains(where: { $0.id == expectedFolder.id }))
        XCTAssertNil(defaults.string(forKey: "pendingImportBackupPath"))
    }

    func testShouldRunAutoBackupWaitsForInitialLoad() {
        let shouldSkip = BackupManager.shared.shouldRunAutoBackup(
            frequency: .daily,
            lastBackupDate: .distantPast,
            hasBackupDestination: true,
            hasLoadedInitialNotes: false,
            now: Date()
        )
        XCTAssertFalse(shouldSkip)

        let shouldRun = BackupManager.shared.shouldRunAutoBackup(
            frequency: .daily,
            lastBackupDate: .distantPast,
            hasBackupDestination: true,
            hasLoadedInitialNotes: true,
            now: Date()
        )
        XCTAssertTrue(shouldRun)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "BackupManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeBackupDirectory(
        notes: [Note]? = nil,
        folders: [Folder]? = nil,
        includeNotes: Bool = true,
        includeFolders: Bool = true,
        corruptNotes: Bool = false
    ) throws -> URL {
        let notes = notes ?? [Note(title: "Backup Note", content: "Body")]
        let folders = folders ?? [Folder(name: "Backup Folder")]
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let manifest = BackupManager.BackupManifest(
            appVersion: "test",
            schemaVersion: 2,
            timestamp: Date(),
            noteCount: notes.count,
            folderCount: folders.count,
            smartFolderCount: 0
        )
        try makeBackupEncoder().encode(manifest)
            .write(to: backupURL.appendingPathComponent("manifest.json"))

        if includeNotes {
            let notesURL = backupURL.appendingPathComponent("notes.json")
            if corruptNotes {
                try Data("not-json".utf8).write(to: notesURL)
            } else {
                try makeBackupEncoder().encode(notes).write(to: notesURL)
            }
        }

        if includeFolders {
            try makeBackupEncoder().encode(folders)
                .write(to: backupURL.appendingPathComponent("folders.json"))
        }

        try makeBackupEncoder().encode([SmartFolder]())
            .write(to: backupURL.appendingPathComponent("smartFolders.json"))

        return backupURL
    }

    private func makeStoreTriplet() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupManagerStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeBaseURL = directoryURL.appendingPathComponent("default.store", isDirectory: false)

        for suffix in ["", "-wal", "-shm"] {
            _ = FileManager.default.createFile(
                atPath: storeBaseURL.path + suffix,
                contents: Data("store".utf8)
            )
        }

        return storeBaseURL
    }

    private func assertStoreTripletExists(at storeBaseURL: URL, file: StaticString = #filePath, line: UInt = #line) {
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: storeBaseURL.path + suffix),
                "Expected store file \(suffix) to exist",
                file: file,
                line: line
            )
        }
    }

    private func assertStoreTripletMissing(at storeBaseURL: URL, file: StaticString = #filePath, line: UInt = #line) {
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: storeBaseURL.path + suffix),
                "Expected store file \(suffix) to be removed",
                file: file,
                line: line
            )
        }
    }

    private func makeBackupEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
