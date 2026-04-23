import XCTest
@testable import Jot

@MainActor
final class NoteQuickLookTests: XCTestCase {

    func testGenerateContainsTitleTagsAndRenderedBody() {
        let note = Note(
            title: "My Note",
            content: "[[b]]Bold[[/b]] and [[ic]]inline[[/ic]]",
            tags: ["work", "urgent"]
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("<h1>My Note</h1>"), "Expected note title in Quick Look HTML: \(html)")
        XCTAssertTrue(html.contains("work"), "Expected work tag in Quick Look HTML: \(html)")
        XCTAssertTrue(html.contains("urgent"), "Expected urgent tag in Quick Look HTML: \(html)")
        XCTAssertTrue(html.contains("<strong>Bold</strong>"), "Expected bold text to render semantically: \(html)")
        XCTAssertTrue(html.contains("<code>inline</code>"), "Expected inline code to render semantically: \(html)")
        XCTAssertTrue(html.contains("note-markup"), "Expected shared renderer wrapper in Quick Look HTML: \(html)")
    }

    func testGenerateEscapesTitleAndFallsBackForEmptyTitle() {
        let escaped = NotePreviewHTMLGenerator.generate(note: Note(title: "<Script>", content: ""))
        XCTAssertFalse(escaped.contains("<Script>"), "Raw title should not be injected into HTML: \(escaped)")
        XCTAssertTrue(escaped.contains("&lt;Script&gt;"), "Escaped title missing from Quick Look HTML: \(escaped)")

        let untitled = NotePreviewHTMLGenerator.generate(note: Note(title: "", content: ""))
        XCTAssertTrue(untitled.contains("Untitled"), "Empty title should fall back to Untitled: \(untitled)")
    }

    func testInlineTextViewClearQuickLookPreviewStopsSecurityScope() {
        let textView = InlineNSTextView(frame: .zero)
        var stopCount = 0

        textView.setQuickLookPreview(
            url: URL(fileURLWithPath: "/tmp/preview-a"),
            stopAccessing: { stopCount += 1 }
        )
        textView.clearQuickLookPreview()

        XCTAssertEqual(stopCount, 1)
        XCTAssertNil(textView.quickLookPreviewURL)
    }

    func testInlineTextViewReplacingQuickLookPreviewReleasesPreviousSecurityScope() {
        let textView = InlineNSTextView(frame: .zero)
        var firstStopCount = 0
        var secondStopCount = 0

        textView.setQuickLookPreview(
            url: URL(fileURLWithPath: "/tmp/preview-a"),
            stopAccessing: { firstStopCount += 1 }
        )
        textView.setQuickLookPreview(
            url: URL(fileURLWithPath: "/tmp/preview-b"),
            stopAccessing: { secondStopCount += 1 }
        )
        textView.clearQuickLookPreview()

        XCTAssertEqual(firstStopCount, 1)
        XCTAssertEqual(secondStopCount, 1)
        XCTAssertNil(textView.quickLookPreviewURL)
    }
}
