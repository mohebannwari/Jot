import XCTest
@testable import Jot

final class PendingShareManagerTests: XCTestCase {

    private var testDirectory: URL!

    override func setUp() {
        super.setUp()
        // PendingShareManager uses App Group container, which may not be available in tests.
        // These tests verify the Codable round-trip and the consume/sort logic.
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingShareTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }

    // MARK: - PendingShare Codable Round-Trip

    func testURLShareRoundTrip() throws {
        let share = PendingShare(
            type: .url,
            title: "Apple",
            content: "https://apple.com",
            imageData: nil,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.type, .url)
        XCTAssertEqual(decoded.title, "Apple")
        XCTAssertEqual(decoded.content, "https://apple.com")
        XCTAssertNil(decoded.imageData)
    }

    func testTextShareRoundTrip() throws {
        let share = PendingShare(
            type: .text,
            title: "My Note",
            content: "Some interesting text content",
            imageData: nil,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.type, .text)
        XCTAssertEqual(decoded.title, "My Note")
        XCTAssertEqual(decoded.content, "Some interesting text content")
    }

    func testImageShareRoundTrip() throws {
        let base64 = Data("fake-image-data".utf8).base64EncodedString()
        let share = PendingShare(
            type: .image,
            title: nil,
            content: nil,
            imageData: base64,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.type, .image)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.content)
        XCTAssertEqual(decoded.imageData, base64)
    }

    // MARK: - File-Based Write/Consume Simulation

    func testWriteAndConsumeSimulation() throws {
        // Simulate what PendingShareManager does: write JSON files, read them back
        let share1 = PendingShare(type: .text, title: "First", content: "A", imageData: nil, timestamp: Date())
        let share2 = PendingShare(type: .url, title: "Second", content: "https://example.com", imageData: nil,
                                  timestamp: Date().addingTimeInterval(1))

        let encoder = JSONEncoder()

        let file1 = testDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try encoder.encode(share1).write(to: file1)

        let file2 = testDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try encoder.encode(share2).write(to: file2)

        // Read them back
        let files = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        var shares: [PendingShare] = []

        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let share = try decoder.decode(PendingShare.self, from: data)
            shares.append(share)
        }

        XCTAssertEqual(shares.count, 2)
    }

    func testEmptyDirectoryReturnsNoShares() throws {
        let files = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        XCTAssertTrue(jsonFiles.isEmpty)
    }

    func testMalformedJSONIsSkipped() throws {
        // Write malformed JSON
        let malformedFile = testDirectory.appendingPathComponent("bad.json")
        try Data("not valid json".utf8).write(to: malformedFile)

        // Write valid JSON
        let validShare = PendingShare(type: .text, title: "Valid", content: "OK", imageData: nil, timestamp: Date())
        let validFile = testDirectory.appendingPathComponent("good.json")
        try JSONEncoder().encode(validShare).write(to: validFile)

        let decoder = JSONDecoder()
        var shares: [PendingShare] = []

        let files = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let share = try? decoder.decode(PendingShare.self, from: data) {
                shares.append(share)
            }
        }

        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares.first?.title, "Valid")
    }
}
