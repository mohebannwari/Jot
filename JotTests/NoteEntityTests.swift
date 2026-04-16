import XCTest
@testable import Jot

/// Covers `NoteEntity.extractWebClipData` behavior around the `[[webclip|T|D|U]]` marker,
/// specifically the regression where deleting the marker left `isWebClip == true` forever.
@MainActor
final class NoteEntityTests: XCTestCase {

    // MARK: - Web clip extraction on content update

    /// Content with a valid marker populates webClipURL/Title/Description.
    func testUpdateContent_PopulatesWebClipFieldsFromMarker() {
        let entity = NoteEntity(title: "Article", content: "original")
        entity.updateContent("[[webclip|Example Title|A short description|https://example.com]]")

        XCTAssertEqual(entity.webClipTitle, "Example Title")
        XCTAssertEqual(entity.webClipDescription, "A short description")
        XCTAssertEqual(entity.webClipURL, "https://example.com")
        XCTAssertTrue(entity.isWebClip)
    }

    /// Deleting the marker must clear the extracted fields — previously the method only wrote
    /// fields on match and never cleared them on miss, so `isWebClip` stayed true forever.
    func testUpdateContent_ClearsWebClipFieldsWhenMarkerRemoved() {
        let entity = NoteEntity(title: "Article", content: "")
        entity.updateContent("[[webclip|t|d|https://example.com]]")
        XCTAssertTrue(entity.isWebClip, "precondition: marker set webclip fields")

        entity.updateContent("Just plain text now, no marker.")

        XCTAssertNil(entity.webClipURL,
            "After marker removal, webClipURL must be nil so isWebClip returns false")
        XCTAssertNil(entity.webClipTitle)
        XCTAssertNil(entity.webClipDescription)
        XCTAssertFalse(entity.isWebClip)
    }

    /// Marker embedded in the middle of non-webclip content still extracts — this matches
    /// existing behavior and is left unchanged (regression guard so future refactors don't
    /// accidentally tighten the matcher).
    func testUpdateContent_ExtractsFromMiddleOfContent() {
        let entity = NoteEntity(title: "n", content: "")
        entity.updateContent("preamble [[webclip|T|D|https://x.com]] epilogue")
        XCTAssertEqual(entity.webClipURL, "https://x.com")
    }

    /// Replacing one marker with another should update fields, not retain the old values.
    func testUpdateContent_SwappingMarkerUpdatesFields() {
        let entity = NoteEntity(title: "n", content: "")
        entity.updateContent("[[webclip|First|d1|https://first.com]]")
        XCTAssertEqual(entity.webClipURL, "https://first.com")

        entity.updateContent("[[webclip|Second|d2|https://second.com]]")
        XCTAssertEqual(entity.webClipURL, "https://second.com")
        XCTAssertEqual(entity.webClipTitle, "Second")
    }

    /// `updateContent` with identical content must still update modifiedAt but MUST NOT clear
    /// web clip fields. Previously the function ran extractWebClipData unconditionally; now
    /// it skips the regex scan on no-op writes. This test ensures the skip doesn't regress
    /// the marker state.
    func testUpdateContent_NoopWriteDoesNotClearWebClipFields() {
        let entity = NoteEntity(title: "n", content: "")
        entity.updateContent("[[webclip|T|D|https://example.com]]")
        XCTAssertEqual(entity.webClipURL, "https://example.com")

        // Write the same content back — this happens during autosave flushes that round-trip
        // identical strings through the binding.
        entity.updateContent(entity.content)
        XCTAssertEqual(entity.webClipURL, "https://example.com",
            "Re-writing identical content must not clear web clip fields")
    }
}
