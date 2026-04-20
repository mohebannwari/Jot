import XCTest
@testable import Jot

@MainActor
final class AttachmentStorageManagerFilenameValidationTests: XCTestCase {

    private var testBaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentStorageManagerFilenameValidationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testBaseURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let testBaseURL {
            try? FileManager.default.removeItem(at: testBaseURL)
        }
        testBaseURL = nil
        try super.tearDownWithError()
    }

    func testImageStorageRejectsInvalidStoredFilenamesAndKeepsValidFileInRoot() throws {
        let manager = ImageStorageManager(storageBaseURL: testBaseURL)
        guard let storageRoot = manager.getStorageDirectoryForSync() else {
            return XCTFail("Expected an image storage root")
        }

        let parentEscapeURL = storageRoot.deletingLastPathComponent().appendingPathComponent("foo")
        let rootedAbsoluteCandidateURL = storageRoot.appendingPathComponent("tmp/x", isDirectory: false)
        let rootedMultiComponentURL = storageRoot.appendingPathComponent("a/b", isDirectory: false)
        let validURL = storageRoot.appendingPathComponent("valid-image.jpg", isDirectory: false)

        try writeFixture(at: parentEscapeURL)
        try writeFixture(at: rootedAbsoluteCandidateURL)
        try writeFixture(at: rootedMultiComponentURL)
        try writeFixture(at: validURL)

        XCTAssertNil(manager.getImageURL(for: "../foo"))
        XCTAssertNil(manager.getImageURL(for: "/tmp/x"))
        XCTAssertNil(manager.getImageURL(for: "a/b"))
        XCTAssertEqual(manager.getImageURL(for: "valid-image.jpg"), validURL)

        manager.deleteImage(filename: "../foo")
        manager.deleteImage(filename: "/tmp/x")
        manager.deleteImage(filename: "a/b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentEscapeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootedAbsoluteCandidateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootedMultiComponentURL.path))

        manager.deleteImage(filename: "valid-image.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: validURL.path))
    }

    func testFileStorageRejectsInvalidStoredFilenamesAndKeepsValidFileInRoot() throws {
        let manager = FileAttachmentStorageManager(storageBaseURL: testBaseURL)
        let storageRoot = try manager.storageDirectoryURLSync()

        let parentEscapeURL = storageRoot.deletingLastPathComponent().appendingPathComponent("foo")
        let rootedAbsoluteCandidateURL = storageRoot.appendingPathComponent("tmp/x", isDirectory: false)
        let rootedMultiComponentURL = storageRoot.appendingPathComponent("a/b", isDirectory: false)
        let validURL = storageRoot.appendingPathComponent("valid-file.pdf", isDirectory: false)

        try writeFixture(at: parentEscapeURL)
        try writeFixture(at: rootedAbsoluteCandidateURL)
        try writeFixture(at: rootedMultiComponentURL)
        try writeFixture(at: validURL)

        XCTAssertNil(manager.fileURL(for: "../foo"))
        XCTAssertNil(manager.fileURL(for: "/tmp/x"))
        XCTAssertNil(manager.fileURL(for: "a/b"))
        XCTAssertEqual(manager.fileURL(for: "valid-file.pdf"), validURL)

        manager.deleteFile(named: "../foo")
        manager.deleteFile(named: "/tmp/x")
        manager.deleteFile(named: "a/b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentEscapeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootedAbsoluteCandidateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootedMultiComponentURL.path))

        manager.deleteFile(named: "valid-file.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: validURL.path))
    }

    private func writeFixture(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: url)
    }
}
