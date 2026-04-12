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
        XCTAssertEqual(engine.results.first?.note?.id, n1.id)
    }

    @MainActor
    func testTagMatchScored() {
        let engine = SearchEngine()
        let n = Note(title: "Title", content: "Body", tags: ["swift", "notes"])
        engine.query = "swift"
        engine.setNotes([n])
        XCTAssertEqual(engine.results.count, 1)
        XCTAssertEqual(engine.results.first?.note?.id, n.id)
    }

    @MainActor
    func testSetNotesAfterQueryComputesImmediately() {
        let engine = SearchEngine()
        let n = Note(title: "MatchMe", content: "")
        engine.query = "match"
        engine.setNotes([n]) // triggers performSearch immediately
        XCTAssertEqual(engine.results.first?.note?.id, n.id)
    }

    @MainActor
    func testCommittedQueriesDedupedAndOrderedNewestFirst() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        engine.recordCommittedQuery("alpha")
        engine.recordCommittedQuery("beta")
        engine.recordCommittedQuery("gamma")
        engine.recordCommittedQuery("beta")
        engine.recordCommittedQuery("delta")

        let queries = engine.paletteHistory.compactMap(\.queryText)
        XCTAssertEqual(queries, ["delta", "beta", "gamma", "alpha"])
        XCTAssertTrue(engine.paletteHistory.allSatisfy { $0.isQuery })
    }

    @MainActor
    func testPaletteHistoryCombinedCapFive() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        engine.recordCommittedQuery("one")
        engine.recordCommittedQuery("two")
        engine.recordCommittedQuery("three")

        var notes: [Note] = []
        for i in 0..<4 {
            var n = Note(title: "N\(i)", content: "")
            n.id = UUID()
            notes.append(n)
        }
        engine.setNotes(notes)
        for n in notes {
            engine.recordOpenedFromSearch(note: n)
        }

        XCTAssertEqual(engine.paletteHistory.count, 5)
        // Newest four note opens plus the most recent committed query survive the combined cap.
        XCTAssertEqual(engine.paletteHistory.first?.openedTarget?.entityID, notes[3].id)
        XCTAssertEqual(engine.paletteHistory.last?.queryText, "three")
    }

    @MainActor
    func testPaletteHistoryPersistAcrossInstances() {
        let key = "search-recent-\(UUID().uuidString)"
        let openedKey = "search-opened-\(UUID().uuidString)"
        let paletteKey = "search-palette-\(UUID().uuidString)"
        let suiteName = "SearchEngineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SearchEngine(
            userDefaults: defaults,
            recentQueriesKey: key,
            recentOpenedFromSearchKey: openedKey,
            paletteHistoryKey: paletteKey)
        first.recordCommittedQuery("first")
        first.recordCommittedQuery("second")

        let second = SearchEngine(
            userDefaults: defaults,
            recentQueriesKey: key,
            recentOpenedFromSearchKey: openedKey,
            paletteHistoryKey: paletteKey)
        XCTAssertEqual(second.paletteHistory.compactMap(\.queryText), ["second", "first"])
    }

    @MainActor
    func testOpenedFromSearchCappedAndDedupedWithinCombinedHistory() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var notes: [Note] = []
        for i in 0..<7 {
            var n = Note(title: "N\(i)", content: "")
            n.id = UUID()
            notes.append(n)
        }
        engine.setNotes(notes)
        for n in notes {
            engine.recordOpenedFromSearch(note: n)
        }
        XCTAssertEqual(engine.paletteHistory.count, 5)
        XCTAssertEqual(engine.paletteHistory.first?.openedTarget?.entityID, notes[6].id)
        engine.recordOpenedFromSearch(note: notes[0])
        XCTAssertEqual(engine.paletteHistory.first?.openedTarget?.entityID, notes[0].id)
        XCTAssertEqual(engine.paletteHistory.count, 5)
    }

    @MainActor
    func testOpenedFromSearchPersistAcrossInstances() {
        let key = "search-recent-\(UUID().uuidString)"
        let openedKey = "search-opened-\(UUID().uuidString)"
        let paletteKey = "search-palette-\(UUID().uuidString)"
        let suiteName = "SearchEngineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var n = Note(title: "Persist", content: "")
        let first = SearchEngine(
            userDefaults: defaults,
            recentQueriesKey: key,
            recentOpenedFromSearchKey: openedKey,
            paletteHistoryKey: paletteKey)
        first.setNotes([n])
        first.recordOpenedFromSearch(note: n)

        let second = SearchEngine(
            userDefaults: defaults,
            recentQueriesKey: key,
            recentOpenedFromSearchKey: openedKey,
            paletteHistoryKey: paletteKey)
        XCTAssertEqual(second.paletteHistory.count, 1)
        XCTAssertEqual(second.paletteHistory.first?.openedTarget?.title, "Persist")
    }

    @MainActor
    func testRemoveRecentOpenedTarget() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var n = Note(title: "X", content: "")
        engine.setNotes([n])
        engine.recordOpenedFromSearch(note: n)
        engine.removeRecentOpenedTarget(entityID: n.id)
        XCTAssertTrue(engine.paletteHistory.isEmpty)
    }

    @MainActor
    func testPruneRecentOpenedNoteWhenNoteRemoved() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var n = Note(title: "Gone", content: "")
        engine.setNotes([n])
        engine.recordOpenedFromSearch(note: n)
        engine.setNotes([])
        XCTAssertTrue(engine.paletteHistory.isEmpty)
    }

    @MainActor
    func testTypingQueryDoesNotRecordRecentQuery() {
        let (engine, defaults, suiteName) = makeIsolatedSearchEngine()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        engine.query = "typed only"
        XCTAssertTrue(engine.paletteHistory.isEmpty)

        engine.recordCommittedQuery(engine.query)
        XCTAssertEqual(engine.paletteHistory.compactMap(\.queryText), ["typed only"])
    }

    @MainActor
    private func makeIsolatedSearchEngine() -> (SearchEngine, UserDefaults, String) {
        let key = "search-recent-\(UUID().uuidString)"
        let openedKey = "search-opened-\(UUID().uuidString)"
        let paletteKey = "search-palette-\(UUID().uuidString)"
        let suiteName = "SearchEngineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SearchEngine(
            userDefaults: defaults,
            recentQueriesKey: key,
            recentOpenedFromSearchKey: openedKey,
            paletteHistoryKey: paletteKey)
        return (engine, defaults, suiteName)
    }
}
