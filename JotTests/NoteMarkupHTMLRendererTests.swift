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

    func testQuickLookRendersCardsTabsTrailingQuotesAndBareTodos() {
        let cards = CardSectionData(
            columns: [
                [
                    CardData(content: "[[b]]Alpha[[/b]]", color: .emerald, width: 450, height: 350)
                ],
                [
                    CardData(content: "[[quote]]Quoted[[/quote]]", color: .pink, width: 450, height: 350)
                ],
            ]
        ).serialize()
        let tabs = TabsContainerData(
            panes: [
                TabPane(name: "Tab 1", content: "[[quote]]Lead[[/quote]]Tail\n[ ]\n[x] Done", colorHex: "#22C55E"),
                TabPane(name: "Tab 2", content: "Hidden body", colorHex: "#F59E0B"),
            ],
            activeIndex: 0,
            containerHeight: 222,
            preferredContentWidth: nil
        ).serialize()
        let note = Note(
            title: "Structured",
            content: [cards, tabs].joined(separator: "\n")
        )

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("cards-section"), "Expected cards section HTML: \(html)")
        XCTAssertTrue(html.contains("tabs-section"), "Expected tabs section HTML: \(html)")
        XCTAssertTrue(html.contains("Alpha"), "Expected card body content to render: \(html)")
        XCTAssertTrue(html.contains("Tab 1"), "Expected active tab label: \(html)")
        XCTAssertFalse(html.contains("Hidden body"), "Inactive tab content should not render: \(html)")
        XCTAssertTrue(html.contains("<blockquote>"), "Expected quote markup to render semantically: \(html)")
        XCTAssertTrue(html.contains(">Tail<"), "Trailing text after a quote should remain visible: \(html)")
        XCTAssertTrue(html.contains("todo-list"), "Bare todo tokens should render as todo items: \(html)")
        XCTAssertFalse(html.contains("[[cards|"), "Quick Look leaked cards token: \(html)")
        XCTAssertFalse(html.contains("[[tabs|"), "Quick Look leaked tabs token: \(html)")
        XCTAssertFalse(html.contains("[[quote]]Lead[[/quote]]Tail"), "Quick Look leaked inline quote token: \(html)")
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

    func testHTMLExportMatchesQuickLookForCardsAndTabs() {
        let cards = CardSectionData(
            columns: [[CardData(content: "Visible card", color: .blue, width: 450, height: 350)]]
        ).serialize()
        let tabs = TabsContainerData(
            panes: [
                TabPane(name: "Summary", content: "[x] Done", colorHex: "#3B82F6"),
                TabPane(name: "Hidden", content: "Should stay hidden", colorHex: nil),
            ],
            activeIndex: 0,
            containerHeight: 222,
            preferredContentWidth: nil
        ).serialize()
        let note = Note(
            title: "Parity",
            content: [cards, tabs].joined(separator: "\n")
        )

        let quickLook = NotePreviewHTMLGenerator.generate(note: note)
        let exported = NoteExportService.shared.buildHTMLString(notes: [note], title: "Parity")

        XCTAssertTrue(quickLook.contains("cards-section"), "Quick Look should render cards semantically: \(quickLook)")
        XCTAssertTrue(exported.contains("cards-section"), "HTML export should render cards semantically: \(exported)")
        XCTAssertTrue(quickLook.contains("tabs-section"), "Quick Look should render tabs semantically: \(quickLook)")
        XCTAssertTrue(exported.contains("tabs-section"), "HTML export should render tabs semantically: \(exported)")
        XCTAssertFalse(quickLook.contains("[[cards|"), "Quick Look leaked cards token: \(quickLook)")
        XCTAssertFalse(exported.contains("[[tabs|"), "HTML export leaked tabs token: \(exported)")
    }

    func testQuickLookTableUsesSerializedColumnWidths() {
        let table = NoteTableData(
            columns: 3,
            cells: [["Step", "Skill", "What to do"], ["1", "`superpowers:brainstorming`", "Refine the spec with clarifying questions."]],
            columnWidths: [88, 260, 520]
        ).serialize()
        let note = Note(title: "Widths", content: table)

        let html = NotePreviewHTMLGenerator.generate(note: note)

        XCTAssertTrue(html.contains("<colgroup>"), "Expected table colgroup so narrow columns do not collapse: \(html)")
        XCTAssertTrue(html.contains("width:88px"), "Expected first column width to be honored: \(html)")
        XCTAssertTrue(html.contains("width:260px"), "Expected second column width to be honored: \(html)")
        XCTAssertTrue(html.contains("min-width:868px"), "Expected table min-width to follow serialized widths: \(html)")
    }
}
