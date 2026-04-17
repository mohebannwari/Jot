import XCTest
@testable import Jot

@MainActor
final class BuildWatcherManagerTests: XCTestCase {

    /// Temporary base directories created during tests, removed in `tearDown`.
    private var createdBaseDirs: [URL] = []

    override func tearDown() async throws {
        // Remove every temp dir created by this test run. Previously the tests left
        // `Jot.app` bundles in the sandbox tmp dir on every run, which macOS
        // LaunchServices auto-registered (via FSEvents) and never pruned — producing
        // hundreds of phantom `Jot.app` registrations that eventually broke
        // double-click launch of the real app (LS resolved to a dead path).
        //
        // Deleting the temp dirs here prevents that accumulation at the source.
        // The directory structure below also intentionally does NOT use `.app` so
        // LaunchServices ignores it entirely — a belt to the tearDown suspenders.
        for baseURL in createdBaseDirs {
            try? FileManager.default.removeItem(at: baseURL)
        }
        createdBaseDirs.removeAll()
        try await super.tearDown()
    }

    /// Creates a temporary executable file in a plain directory (no `.app` extension
    /// or `Contents/MacOS` nesting). `BuildWatcherManager.watchedBinaryURL(for:)` only
    /// checks for a sibling `<name>.debug.dylib`; the `.app` bundle structure wasn't
    /// needed — and its presence triggered LaunchServices auto-registration that
    /// polluted the user-domain LS database on every test run.
    private func makeTemporaryExecutableURL(testName: String) throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildWatcherManagerTests-\(testName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        createdBaseDirs.append(baseURL)

        let executableURL = baseURL.appendingPathComponent("Jot")
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
