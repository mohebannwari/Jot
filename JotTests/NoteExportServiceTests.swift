import XCTest
import PDFKit
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
        XCTAssertEqual(out, "-> next")
    }

    func testConvertMarkupToHTML_arrow() {
        let out = NoteExportService.shared.convertMarkupToHTML("[[arrow]]")
        XCTAssertTrue(out.contains("&rarr;"), "Got: \(out)")
    }

    func testConvertMarkupToPlainText_arrow() {
        let out = NoteExportService.shared.convertMarkupToPlainText("[[arrow]]")
        XCTAssertEqual(out, "\u{2192}")
    }

    func testRawLiteralTokensSurviveMarkdownAndPlainTextExport() {
        let literal = JotMarkupLiteral.encode("[[h3]]")

        XCTAssertEqual(
            NoteExportService.shared.convertMarkupToMarkdown("[[ic]]\(literal)[[/ic]]"),
            "`[[h3]]`"
        )
        XCTAssertEqual(
            NoteExportService.shared.convertMarkupToPlainText("[[ic]]\(literal)[[/ic]]"),
            "[[h3]]"
        )
    }

    func testMarkdownExportSerializesRichFixtureAsReadableGFM() {
        let note = Self.richExportFixture()
        let markdown = NoteExportService.shared.buildMarkdownString(notes: [note])

        XCTAssertTrue(markdown.contains("# Export Fixture"), markdown)
        XCTAssertTrue(markdown.contains("## Section"), markdown)
        XCTAssertTrue(markdown.contains("- Bullet item"), markdown)
        XCTAssertTrue(markdown.contains("2. Ordered item"), markdown)
        XCTAssertTrue(markdown.contains("- [x] Done item"), markdown)
        XCTAssertTrue(markdown.contains("- [ ] Todo item"), markdown)
        XCTAssertTrue(markdown.contains("[Jot](https://jot.test)"), markdown)
        XCTAssertTrue(markdown.contains("`[[h3]]`"), markdown)
        XCTAssertTrue(markdown.contains("```swift\nlet value = \"[[h3]]\"\n```"), markdown)
        XCTAssertTrue(markdown.contains("| Feature | Result |"), markdown)
        XCTAssertTrue(markdown.contains("| --- | --- |"), markdown)
        XCTAssertTrue(markdown.contains("> [!warning]"), markdown)
        XCTAssertTrue(markdown.contains("![Image]("), markdown)
        XCTAssertTrue(markdown.contains("[Spec.pdf]"), markdown)
        XCTAssertTrue(markdown.contains("---"), markdown)
        XCTAssertFalse(markdown.contains("[[table|"), markdown)
        XCTAssertFalse(markdown.contains("[[callout|"), markdown)
        XCTAssertFalse(markdown.contains("[[codeblock|"), markdown)
        XCTAssertFalse(markdown.contains("[Table]"), markdown)
    }

    func testPlainTextExportFlattensRichFixtureWithoutStorageTokens() {
        let text = NoteExportService.shared.buildPlainTextString(notes: [Self.richExportFixture()])

        XCTAssertTrue(text.contains("Export Fixture"), text)
        XCTAssertTrue(text.contains("Section"), text)
        XCTAssertTrue(text.contains("Feature\tResult"), text)
        XCTAssertTrue(text.contains("Done item"), text)
        XCTAssertTrue(text.contains("[done] Done item"), text)
        XCTAssertTrue(text.contains("Jot (https://jot.test)"), text)
        XCTAssertTrue(text.contains("[[h3]]"), text)
        XCTAssertTrue(text.contains("let value = \"[[h3]]\""), text)
        XCTAssertFalse(text.contains("[[table|"), text)
        XCTAssertFalse(text.contains("[[callout|"), text)
        XCTAssertFalse(text.contains("[[codeblock|"), text)
        XCTAssertFalse(text.contains("[Table]"), text)
    }

    func testHTMLExportUsesSharedSemanticRendererForRichBlocks() {
        let note = Self.richExportFixture()
        let html = NoteExportService.shared.buildHTMLString(notes: [note], title: "Fixture")
        let quickLook = NotePreviewHTMLGenerator.generate(note: note)

        for marker in ["note-markup", "table-wrapper", "code-block", "callout callout-warning", "attachment-chip"] {
            XCTAssertTrue(html.contains(marker), "Missing \(marker): \(html)")
            XCTAssertTrue(quickLook.contains(marker), "Quick Look missing \(marker): \(quickLook)")
        }

        XCTAssertFalse(html.contains("[[table|"), html)
        XCTAssertFalse(html.contains("[[callout|"), html)
        XCTAssertFalse(html.contains("[[codeblock|"), html)
    }

    func testPDFExportUsesRenderedHTMLAndPaginatesLongContent() async throws {
        let note = Self.longPDFExportFixture()
        let builtData = await NoteExportService.shared.buildPDFData(notes: [note])
        let data = try XCTUnwrap(builtData)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(document.pageCount, 1, "Long export should paginate instead of truncating into one page")

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertTrue(text.contains("Export Fixture"), text)
        XCTAssertTrue(text.contains("Long line 119"), text)
        XCTAssertFalse(text.contains("[[h3]]Section"), text)
        XCTAssertFalse(text.contains("[[codeblock|"), text)
    }

    private static func richExportFixture() -> Note {
        let literalHeading = JotMarkupLiteral.encode("[[h3]]")
        let table = NoteTableData(
            columns: 2,
            cells: [
                ["Feature", "Result"],
                ["Tables", "GFM clean"],
                ["Literal", "[[h3]] stays text"],
            ],
            columnWidths: [160, 220],
            wrapText: true
        ).serialize()
        let callout = CalloutData(type: .warning, content: "Careful with tokens").serialize()
        let code = CodeBlockData(language: "swift", code: "let value = \"[[h3]]\"").serialize()
        let content = [
            "[[h1]]Section[[/h1]]",
            "- Bullet item",
            "[[ol|2]]Ordered item",
            "[x] Done item",
            "[ ] Todo item",
            "[[link|https://jot.test|Jot]] and [[ic]]\(literalHeading)[[/ic]]",
            code,
            table,
            callout,
            "[[image|||missing-image.png]]",
            "[[file|pdf|stored.pdf|Spec.pdf]]",
            "[[divider]]",
        ].joined(separator: "\n")

        return Note(title: "Export Fixture", content: content, tags: ["export", "format"])
    }

    private static func longPDFExportFixture() -> Note {
        let body = (0..<120)
            .map { "Long line \($0): export should keep this searchable and paginated." }
            .joined(separator: "\n")
        return Note(
            title: "Export Fixture",
            content: "[[h1]]Section[[/h1]]\n\(body)\n\(CodeBlockData(language: "swift", code: "let token = \"[[h3]]\"").serialize())"
        )
    }
}
