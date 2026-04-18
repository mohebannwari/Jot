import XCTest
@testable import Jot

/// Round-trip expectations for `NoteExportService` markup → export formats.
@MainActor
final class NoteExportServiceTests: XCTestCase {

    func testConvertMarkupToMarkdown_inlineCode() {
        let out = NoteExportService.shared.convertMarkupToMarkdown("[[ic]]a b[[/ic]]")
        XCTAssertEqual(out, "`a b`")
    }

    func testConvertMarkupToMarkdown_labeledLink() {
        let out = NoteExportService.shared.convertMarkupToMarkdown("[[link|https://x.com|Click]]")
        XCTAssertEqual(out, "[Click](https://x.com)")
    }

    func testConvertMarkupToMarkdown_bareLink() {
        let out = NoteExportService.shared.convertMarkupToMarkdown("[[link|https://x.com]]")
        XCTAssertEqual(out, "[https://x.com](https://x.com)")
    }

    func testConvertMarkupToMarkdown_orderedListPrefix() {
        let out = NoteExportService.shared.convertMarkupToMarkdown("[[ol|3]]Step")
        XCTAssertEqual(out, "3. Step")
    }

    func testConvertMarkupToHTML_inlineCodeAndLabeledLink() {
        let out = NoteExportService.shared.convertMarkupToHTML("[[ic]]x[[/ic]] [[link|https://a.org|A]]")
        XCTAssertTrue(out.contains("<code>x</code>"), "Got: \(out)")
        XCTAssertTrue(out.contains(#"<a href="https://a.org">A</a>"#), "Got: \(out)")
    }

    func testConvertMarkupToPlainText_stripsIcAndExpandsLabeledLink() {
        let out = NoteExportService.shared.convertMarkupToPlainText("[[ic]]x[[/ic]] [[link|https://a.org|A]]")
        XCTAssertEqual(out, "x A (https://a.org)")
    }

    func testConvertMarkupToMarkdown_arrow() {
        let out = NoteExportService.shared.convertMarkupToMarkdown("[[arrow]] next")
        XCTAssertEqual(out, "->  next")
    }

    func testConvertMarkupToHTML_arrow() {
        let out = NoteExportService.shared.convertMarkupToHTML("[[arrow]]")
        XCTAssertTrue(out.contains("&rarr;"), "Got: \(out)")
    }

    func testConvertMarkupToPlainText_arrow() {
        let out = NoteExportService.shared.convertMarkupToPlainText("[[arrow]]")
        XCTAssertEqual(out, "\u{2192}")
    }
}
