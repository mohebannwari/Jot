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

    func testMarkdownNestedListsAndTaskListsPreserveStructure() async {
        let md = """
        - Parent
          - Child
        - [x] Done
        - [ ] Todo
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines[0], "• Parent", "Got: \(content.debugDescription)")
        XCTAssertEqual(lines[1], "  • Child", "Nested list indentation must survive import; got: \(content.debugDescription)")
        XCTAssertEqual(lines[2], "[x] Done", "Checked GFM task list item must survive; got: \(content.debugDescription)")
        XCTAssertEqual(lines[3], "[ ] Todo", "Unchecked GFM task list item must survive; got: \(content.debugDescription)")
    }

    func testMarkdownGFMTableCreatesPlainSafeTableBlock() async throws {
        let md = """
        | Task | Skill |
        | --- | --- |
        | One | `[[h3]]` |
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )

        let table = try XCTUnwrap(NoteTableData.deserialize(from: content), "Expected GFM table import; got: \(content)")
        XCTAssertEqual(table.columns, 2)
        XCTAssertEqual(table.cells[0], ["Task", "Skill"])
        XCTAssertEqual(table.cells[1], ["One", "[[h3]]"])
        XCTAssertTrue(table.wrapText)

        let html = NotePreviewHTMLGenerator.generate(note: Note(title: "Table", content: content))
        XCTAssertTrue(html.contains("[[h3]]"), "Literal table-cell code text should remain readable, not become a heading: \(html)")
        XCTAssertFalse(html.contains("<h3>"), "Table cell content must not recursively execute Jot heading tags: \(html)")
    }

    func testMarkdownReferenceLinksResolveToLinkTags() async {
        let md = """
        See [Reference][docs].

        [docs]: https://example.com/docs
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )

        XCTAssertTrue(content.contains("[[link|https://example.com/docs|Reference]]"), "Got: \(content)")
    }

    func testMarkdownFencedCodeAndRawHTMLStaySafe() async throws {
        let md = """
        ```swift
        let token = "[[h3]]"
        ```

        <script>alert("x")</script>
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )

        let codeBlockLine = try XCTUnwrap(content.split(separator: "\n").first.map(String.init))
        let codeBlock = try XCTUnwrap(CodeBlockData.deserialize(from: codeBlockLine))
        XCTAssertEqual(codeBlock.language, "swift")
        XCTAssertEqual(codeBlock.code, "let token = \"[[h3]]\"")

        let html = NotePreviewHTMLGenerator.generate(note: Note(title: "HTML", content: content))
        XCTAssertFalse(html.contains("<script>alert"), "Raw HTML from Markdown must not execute in Quick Look: \(html)")
        XCTAssertTrue(html.contains("&lt;script&gt;alert"), "Raw HTML should render as escaped readable text: \(html)")
    }

    func testMarkdownYAMLTitleAndTagsImportThroughPublicEntryPoint() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JotMarkdownImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("fallback.md")
        try """
        ---
        title: YAML Title
        tags:
          - alpha
          - "#beta"
          - alpha
        ---
        Body
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = try SimpleSwiftDataManager(inMemoryForTesting: true)
        let importedNote = await NoteImportService.shared.importFile(at: fileURL, into: manager)
        let note = try XCTUnwrap(importedNote)

        XCTAssertEqual(note.title, "YAML Title")
        XCTAssertEqual(note.content, "Body")
        XCTAssertEqual(note.tags, ["alpha", "beta"])
    }

    func testMarkdownObsidianCalloutBecomesCalloutBlock() async throws {
        let md = """
        > [!danger]- Watch out
        > Body line
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )

        let callout = try XCTUnwrap(CalloutData.deserialize(from: content), "Expected Obsidian callout import; got: \(content)")
        XCTAssertEqual(callout.type, .warning)
        XCTAssertEqual(callout.content, "Watch out\nBody line")
    }

    func testMarkdownLiteralJotMarkupDoesNotBecomeStorageMarkup() async {
        let md = "Reference `[[h3]]`, `[[file|type|stored|name]]`, and `[x]` literally."
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )

        XCTAssertFalse(content.contains("[[ic]][[h3]][[/ic]]"), "Inline code leaked executable Jot heading markup: \(content)")
        XCTAssertFalse(content.contains("[[ic]][[file|type|stored|name]][[/ic]]"), "Inline code leaked executable file markup: \(content)")

        let html = NotePreviewHTMLGenerator.generate(note: Note(title: "Literal", content: content))
        XCTAssertTrue(html.contains("<code>[[h3]]</code>"), "Literal heading marker should remain visible as code: \(html)")
        XCTAssertTrue(html.contains("<code>[[file|type|stored|name]]</code>"), "Literal file marker should remain visible as code: \(html)")
        XCTAssertTrue(html.contains("<code>[x]</code>"), "Literal todo marker should remain visible as code: \(html)")
    }

    func testAttachedAgentsFixtureImportDoesNotCreatePhantomBlocks() async throws {
        let fixtureURL = URL(fileURLWithPath: "/Users/mohebanwari/development/Jot/AGENTS.md")
        let raw = try String(contentsOf: fixtureURL, encoding: .utf8)

        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: raw,
            baseDirectory: fixtureURL.deletingLastPathComponent(),
            fileURLForFallbackTitle: fixtureURL
        )

        XCTAssertFalse(content.contains("\n\n"), "Markdown import should not create empty editor paragraphs: \(content.prefix(1000))")
        XCTAssertFalse(content.contains("[[divider]]\n[[divider]]"), "Adjacent Markdown rules/frontmatter must not become double dividers")
        XCTAssertFalse(content.contains("[[/h3]][[h3]]"), "Heading/list markers should not smear across adjacent blocks")
    }

    // MARK: - Frontmatter validation: only strip leading `---...---` when it's actually YAML

    /// Regression for the AGENTS.md import bug: a leading `---...---` block whose contents
    /// are markdown (headings, bold, prose) was being silently discarded as if it were YAML
    /// frontmatter. The block must now be preserved as body content.
    func testFrontmatterPreservedWhenInteriorIsMarkdownHeading() async {
        let md = """
        ---
        ## description:
        alwaysApply: true
        ---
        ## Real body
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(
            content.contains("description"),
            "Markdown heading inside `---...---` must not be stripped as YAML frontmatter; got: \(content.debugDescription)"
        )
        XCTAssertTrue(
            content.contains("alwaysApply"),
            "Prose inside `---...---` must not be stripped as YAML frontmatter; got: \(content.debugDescription)"
        )
    }

    /// AGENTS.md-shaped fixture: the real file has bold prose + an H1 inside the leading
    /// `---...---`. Importing it must surface the recovered content in the body.
    func testFrontmatterPreservedWhenInteriorContainsBoldProse() async {
        let md = """
        ---
        # Jot -- agent instructions
        **Single source of truth:** edit `AGENTS.md` at the repository root only.
        iOS 26+ note-taking app.
        ---
        ## Forward Thinking
        Body.
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(
            content.contains("Single source of truth"),
            "Bold prose inside `---...---` must survive import; got: \(content.debugDescription)"
        )
        XCTAssertTrue(
            content.contains("iOS 26+ note-taking app"),
            "Plain prose inside `---...---` must survive import; got: \(content.debugDescription)"
        )
    }

    /// A line like `This is a sentence: with a colon.` superficially resembles a YAML key/value
    /// but the "key" contains spaces — invalid. The block must be preserved.
    func testFrontmatterPreservedWhenInteriorIsProseWithColons() async {
        let md = """
        ---
        This is a sentence: with a colon.
        ---
        Body.
        """
        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: md,
            baseDirectory: importTestBaseURL,
            fileURLForFallbackTitle: importTestFileURL
        )
        XCTAssertTrue(
            content.contains("This is a sentence"),
            "Prose with colons inside `---...---` must not be mistaken for YAML; got: \(content.debugDescription)"
        )
    }

    /// Verifies the actual `AGENTS.md` fixture round-trips the previously-dropped chunk
    /// (the user's reported bug). After the fix the body must contain the bold "Single
    /// source of truth" lead and the iOS-26 paragraph.
    func testAGENTSFixtureRecoversPreviouslyDroppedContent() async throws {
        let fixtureURL = URL(fileURLWithPath: "/Users/mohebanwari/development/Jot/AGENTS.md")
        let raw = try String(contentsOf: fixtureURL, encoding: .utf8)

        let (_, content) = await NoteImportService.shared.convertMarkdownDocument(
            raw: raw,
            baseDirectory: fixtureURL.deletingLastPathComponent(),
            fileURLForFallbackTitle: fixtureURL
        )

        // Anchor on phrasing unique to the frontmatter prefix — "Single source of truth"
        // and "iOS 26+" both appear later in the file too, so we need the full sentence
        // from line 11 to prove the previously-dropped chunk was recovered.
        XCTAssertTrue(
            content.contains("note-taking app in SwiftUI"),
            "AGENTS.md import must include the line-11 deployment-target paragraph that lives inside the leading `---...---` block; got prefix: \(content.prefix(1200))"
        )
    }
}
