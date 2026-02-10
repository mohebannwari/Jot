import XCTest
@testable import Jot

final class SearchEngineTests: XCTestCase {
    @MainActor
    func testEmptyQueryHasNoResults() {
        let engine = SearchEngine()
        let notes = [
            Note(title: "Alpha", content: "some content"),
            Note(title: "Beta", content: "other content")
        ]
        engine.query = ""
        engine.setNotes(notes)
        XCTAssertTrue(engine.results.isEmpty)
    }

    @MainActor
    func testTitleMatchBeatsContentMatch() {
        let engine = SearchEngine()
        var n1 = Note(title: "Hello World", content: "nope") // title hit
        var n2 = Note(title: "nothing", content: "Says hello world in body") // content hit
        // Ensure dates don't flip sort order by chance
        n1.date = Date()
        n2.date = Date(timeIntervalSinceNow: -60)
        engine.query = "hello"
        engine.setNotes([n1, n2])
        XCTAssertEqual(engine.results.first?.note.id, n1.id)
    }

    @MainActor
    func testTagMatchScored() {
        let engine = SearchEngine()
        let n = Note(title: "Title", content: "Body", tags: ["swift", "notes"])
        engine.query = "swift"
        engine.setNotes([n])
        XCTAssertEqual(engine.results.count, 1)
        XCTAssertEqual(engine.results.first?.note.id, n.id)
    }

    @MainActor
    func testSetNotesAfterQueryComputesImmediately() {
        let engine = SearchEngine()
        let n = Note(title: "MatchMe", content: "")
        engine.query = "match"
        engine.setNotes([n]) // triggers performSearch immediately
        XCTAssertEqual(engine.results.first?.note.id, n.id)
    }

    @MainActor
    func testRecentQueriesCappedAndDeduplicated() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        engine.recordCommittedQuery("alpha")
        engine.recordCommittedQuery("beta")
        engine.recordCommittedQuery("gamma")
        engine.recordCommittedQuery("beta")
        engine.recordCommittedQuery("delta")

        XCTAssertEqual(engine.recentQueries, ["delta", "beta", "gamma"])
    }

    @MainActor
    func testRecentQueriesPersistAcrossInstances() {
        let key = "search-recent-\(UUID().uuidString)"
        let suiteName = "SearchEngineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SearchEngine(userDefaults: defaults, recentQueriesKey: key)
        first.recordCommittedQuery("first")
        first.recordCommittedQuery("second")

        let second = SearchEngine(userDefaults: defaults, recentQueriesKey: key)
        XCTAssertEqual(second.recentQueries, ["second", "first"])
    }

    @MainActor
    func testTypingQueryDoesNotRecordRecentQuery() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        engine.query = "typed only"
        XCTAssertTrue(engine.recentQueries.isEmpty)

        engine.recordCommittedQuery(engine.query)
        XCTAssertEqual(engine.recentQueries, ["typed only"])
    }

    @MainActor
    private func makeIsolatedSearchEngine() -> (SearchEngine, UserDefaults, String) {
        let key = "search-recent-\(UUID().uuidString)"
        let suiteName = "SearchEngineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SearchEngine(userDefaults: defaults, recentQueriesKey: key)
        return (engine, defaults, suiteName)
    }
}
