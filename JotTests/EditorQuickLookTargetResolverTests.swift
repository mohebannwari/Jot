import XCTest
@testable import Jot

final class EditorQuickLookTargetResolverTests: XCTestCase {
    func testFilePathTargetResolvesExistingFileWithoutSecurityScope() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorQuickLookTargetResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("sample.txt")
        try "preview".write(to: fileURL, atomically: true, encoding: .utf8)

        let target = EditorQuickLookTargetResolver.resolveFileLinkPreviewTarget(
            path: fileURL.path,
            bookmark: ""
        )

        XCTAssertEqual(target?.url, fileURL)
        XCTAssertEqual(target?.requiresSecurityScope, false)
    }

    func testFilePathTargetRejectsMissingFile() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")
            .path

        let target = EditorQuickLookTargetResolver.resolveFileLinkPreviewTarget(
            path: missingPath,
            bookmark: ""
        )

        XCTAssertNil(target)
    }
}
