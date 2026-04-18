import XCTest
@testable import Jot

/// Markdown import normalization: paragraph separators must not become phantom
/// empty paragraphs in the rich text editor.
@MainActor
final class NoteImportServiceTests: XCTestCase {

    func testMarkdownParagraphSeparatorsCollapse() {
        // Simulates `lines.joined(separator: "\n")` after headings/body blocks with blank
        // lines in the source .md — those must become single `\n`, not `\n\n`.
        let raw = "[[h1]]H1[[/h1]]\n\nBody line\n\n[[h2]]H2[[/h2]]\n\nMore"
        let collapsed = NoteImportService.shared.collapseMarkdownParagraphSeparators(raw)
        XCTAssertFalse(
            collapsed.contains("\n\n"),
            "Markdown block separators must not leave double newlines in stored content; got: \(collapsed.debugDescription)"
        )
        XCTAssertTrue(collapsed.contains("[[h1]]"), "Heading markup must be preserved")
        XCTAssertTrue(collapsed.contains("Body line"), "Body text must be preserved")
    }

    func testMarkdownCollapsePreservesEscapedNewlinesInsideCodeBlockTag() {
        // Real newlines only exist between tags; code body uses `\` + `n` pairs from CodeBlockData.serialize(),
        // not literal newline characters — collapse must not strip those.
        let raw = "[[codeblock|plaintext]]line1\\n\\nline2[[/codeblock]]\n\nAfter block"
        let collapsed = NoteImportService.shared.collapseMarkdownParagraphSeparators(raw)
        let expected = "[[codeblock|plaintext]]line1\\n\\nline2[[/codeblock]]\nAfter block"
        XCTAssertEqual(
            collapsed,
            expected,
            "Only markdown paragraph-separator newlines collapse; escaped \\n inside the tag must remain"
        )
    }

    // MARK: - Markdown fidelity (inline code, links, frontmatter, title, arrows)

    private var importTestBaseURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    private var importTestFileURL: URL { URL(fileURLWithPath: "/tmp/NoteImportServiceTests.md") }

    func testInlineCodeWithUnderscoresSurvivesItalicPass() async {
        let md = "Use `read_file` and `grep_search`."
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(content.contains("[[ic]]read_file[[/ic]]"), "Got: \(content)")
        XCTAssertTrue(content.contains("[[ic]]grep_search[[/ic]]"))
        XCTAssertFalse(content.contains("[[b]]read_file[[/b]]"), "Inline code must not be flattened to bold")
    }

    func testLabeledLinkPreservesLabel() async {
        let md = "[Click me](https://x.com)"
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertEqual(content, "[[link|https://x.com|Click me]]")
    }

    func testLabeledLinkCollapsesWhenLabelEqualsURL() async {
        let md = "[https://x.com](https://x.com)"
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertEqual(content, "[[link|https://x.com]]")
    }

    func testAutolinkBracketsBecomeLinkTag() async {
        let md = "See <https://x.com>."
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(content.contains("[[link|https://x.com]]"))
    }

    func testArrowLineStartBecomesArrowTag() async {
        let md = "-> item"
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(content.hasPrefix("[[arrow]] item"), "Got: \(content)")
    }

    func testArrowAutoConversionAtLineStart() async {
        let md = "-> foo\n=> bar"
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(content.hasPrefix("[[arrow]] foo"), "Got: \(content.debugDescription)")
        XCTAssertTrue(content.contains("\n\u{21D2} bar"))
    }

    func testLeadingH1BecomesNoteTitle() async {
        let md = "# My Title\n\nBody"
        let (title, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertEqual(title, "My Title")
        XCTAssertTrue(
            content.hasPrefix("Body"),
            "Leading H1 must be stripped from body without a leading blank paragraph; raw=\(content.debugDescription)")
    }

    func testYAMLFrontmatterStripped() async {
        let md = """
        ---
        title: X
        ---
        # Heading

        After
        """
        let (title, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertEqual(title, "Heading")
        XCTAssertTrue(content.contains("After"))
        XCTAssertFalse(content.contains("title: X"))
    }

    func testURLInsideInlineCodeIsNotLinkified() async {
        let md = "Use `https://example.com/path` here."
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(content.contains("[[ic]]https://example.com/path[[/ic]]"), "Got: \(content)")
        XCTAssertFalse(content.contains("[[link|https://example.com/path]]"), "URL inside backticks must not become [[link|…]]")
    }

    func testMarkdownOrderedListUsesOlTag() async {
        let md = "1. First\n2. Second"
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        let lines = content.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, "Got: \(content.debugDescription)")
        XCTAssertTrue(lines[0].hasPrefix("[[ol|1]]"), "First line must be stylized ordered list; got: \(lines[0])")
        XCTAssertTrue(lines[0].contains("First"), "Got: \(lines[0])")
        XCTAssertTrue(lines[1].hasPrefix("[[ol|2]]"), "Got: \(lines[1])")
        XCTAssertTrue(lines[1].contains("Second"), "Got: \(lines[1])")
    }
}

