import XCTest
@testable import Jot

@MainActor
final class NoteMarkupHTMLRendererTests: XCTestCase {

    func testQuickLookDoesNotLeakDividerInlineCodeOrNoteLinkTokens() {
        let note = Note(
            title: "Renderer",
            content: """
            Intro
            [[divider]]
            [[ic]]inline[[/ic]]
            [[notelink|123E4567-E89B-12D3-A456-426614174000|Mentioned Note]]
            """
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertFalse(html.contains("[[divider]]"), "Quick Look leaked divider token: \(html)")
        XCTAssertFalse(html.contains("[[ic]]"), "Quick Look leaked inline-code token: \(html)")
        XCTAssertFalse(html.contains("[[notelink|"), "Quick Look leaked notelink token: \(html)")
        XCTAssertTrue(html.contains("<code"), "Quick Look should render inline code semantically: \(html)")
        XCTAssertTrue(html.contains("Mentioned Note"), "Quick Look should render the note-link title: \(html)")
    }

    func testQuickLookRendersOrderedBulletAndTodoListsAsSemanticLists() {
        let note = Note(
            title: "Lists",
            content: """
            [[ol|1]]First
            [[ol|2]]Second
            • Bullet
              • Nested bullet
            [ ] Open item
            [x] Done item
            """
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("<ol"), "Expected ordered list markup: \(html)")
        XCTAssertTrue(html.contains("<ul"), "Expected unordered/todo list markup: \(html)")
        XCTAssertFalse(html.contains("[[ol|"), "Quick Look leaked ordered-list token: \(html)")
    }

    func testQuickLookRendersTableCodeBlockAndCalloutBlocks() {
        let table = NoteTableData(
            columns: 2,
            cells: [["Name", "Role"], ["Ada", "Engineer"]],
            columnWidths: [120, 120]
        ).serialize()
        let code = CodeBlockData(language: "swift", code: "let value = 42").serialize()
        let callout = CalloutData(type: .warning, content: "Watch this").serialize()
        let note = Note(
            title: "Blocks",
            content: [table, code, callout].joined(separator: "\n")
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("<table"), "Expected table markup: \(html)")
        XCTAssertTrue(html.contains("<pre"), "Expected code block markup: \(html)")
        XCTAssertTrue(html.contains("callout"), "Expected callout markup: \(html)")
        XCTAssertFalse(html.contains("[[table|"), "Quick Look leaked table token: \(html)")
        XCTAssertFalse(html.contains("[[codeblock|"), "Quick Look leaked code-block token: \(html)")
        XCTAssertFalse(html.contains("[[callout|"), "Quick Look leaked callout token: \(html)")
    }

    func testQuickLookStripsAIBlockMetadata() {
        let note = Note(
            title: "AI",
            content: """
            Visible
            [[ai-block]]
            Hidden metadata
            """
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("Visible"), "Expected visible content to remain: \(html)")
        XCTAssertFalse(html.contains("[[ai-block]]"), "Quick Look leaked AI block marker: \(html)")
        XCTAssertFalse(html.contains("Hidden metadata"), "Quick Look should strip AI metadata: \(html)")
    }

    func testHTMLExportMatchesQuickLookForStructuredMarkup() {
        let table = NoteTableData(
            columns: 2,
            cells: [["Task", "Owner"], ["Preview", "Jot"]],
            columnWidths: [120, 120]
        ).serialize()
        let note = Note(
            title: "Parity",
            content: """
            [[ol|1]]First
            [x] Done
            [[ic]]inline[[/ic]]
            \(table)
            """
        )

        let quickLook = NotePreviewHTMLGenerator.generate(note: note)
        let exported = NoteExportService.shared.buildHTMLString(notes: [note], title: "Parity")

        XCTAssertTrue(quickLook.contains("<table"), "Quick Look should render tables semantically: \(quickLook)")
        XCTAssertTrue(exported.contains("<table"), "HTML export should render tables semantically: \(exported)")
        XCTAssertTrue(quickLook.contains("<code"), "Quick Look should render inline code semantically: \(quickLook)")
        XCTAssertTrue(exported.contains("<code"), "HTML export should render inline code semantically: \(exported)")
        XCTAssertFalse(quickLook.contains("[[ol|"), "Quick Look leaked ordered-list token: \(quickLook)")
        XCTAssertFalse(exported.contains("[[ol|"), "HTML export leaked ordered-list token: \(exported)")
    }
}
