import XCTest
@testable import Jot

@MainActor
final class BuildWatcherManagerTests: XCTestCase {

    private func makeTemporaryExecutableURL(testName: String) throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildWatcherManagerTests-\(testName)-\(UUID().uuidString)")
        let macOSURL = baseURL
            .appendingPathComponent("Jot.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let executableURL = macOSURL.appendingPathComponent("Jot")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        return executableURL
    }

    func testWatchedBinaryURLPrefersDebugDylibWhenPresent() throws {
        let executableURL = try makeTemporaryExecutableURL(testName: #function)
        let debugDylibURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Jot.debug.dylib")
        FileManager.default.createFile(atPath: debugDylibURL.path, contents: Data())

        XCTAssertEqual(
            BuildWatcherManager.watchedBinaryURL(for: executableURL),
            debugDylibURL
        )
    }

    func testWatchedBinaryURLFallsBackToExecutableWhenDebugDylibMissing() throws {
        let executableURL = try makeTemporaryExecutableURL(testName: #function)

        XCTAssertEqual(
            BuildWatcherManager.watchedBinaryURL(for: executableURL),
            executableURL
        )
    }
}
