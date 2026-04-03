// NoteQuickLookTests.swift
// JotTests

import XCTest
@testable import Jot

final class NoteQuickLookTests: XCTestCase {

    // MARK: - escapeHTML

    func testEscapeHTML_ampersand() {
        XCTAssertEqual(NotePreviewHTMLGenerator.escapeHTML("a & b"), "a &amp; b")
    }

    func testEscapeHTML_angleBrackets() {
        XCTAssertEqual(NotePreviewHTMLGenerator.escapeHTML("<b>"), "&lt;b&gt;")
    }

    func testEscapeHTML_quotes() {
        XCTAssertEqual(NotePreviewHTMLGenerator.escapeHTML("say \"hi\""), "say &quot;hi&quot;")
    }

    // MARK: - processInline

    func testInline_bold() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.processInline("Hello [[b]]World[[/b]]"),
            "Hello <strong>World</strong>"
        )
    }

    func testInline_italic() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.processInline("[[i]]slant[[/i]]"),
            "<em>slant</em>"
        )
    }

    func testInline_underline() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.processInline("[[u]]line[[/u]]"),
            "<u>line</u>"
        )
    }

    func testInline_strikethrough() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.processInline("[[s]]dead[[/s]]"),
            "<s>dead</s>"
        )
    }

    func testInline_color() {
        let result = NotePreviewHTMLGenerator.processInline("[[color|#ff0000]]red[[/color]]")
        XCTAssertTrue(result.contains("<span style=\"color:#ff0000\">"), "Expected opening span, got: \(result)")
        XCTAssertTrue(result.contains("red</span>"), "Expected closing span, got: \(result)")
    }

    // MARK: - parseLine

    func testLine_h1() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.parseLine("[[h1]]My Heading[[/h1]]"),
            "<h2>My Heading</h2>"
        )
    }

    func testLine_h2() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.parseLine("[[h2]]Sub[[/h2]]"),
            "<h3>Sub</h3>"
        )
    }

    func testLine_h3() {
        XCTAssertEqual(
            NotePreviewHTMLGenerator.parseLine("[[h3]]Small[[/h3]]"),
            "<h4>Small</h4>"
        )
    }

    func testLine_todoChecked() {
        let result = NotePreviewHTMLGenerator.parseLine("[x] Buy groceries")
        XCTAssertTrue(result.contains("todo-done"), "Expected todo-done class, got: \(result)")
        XCTAssertTrue(result.contains("&#9745;"), "Expected check symbol, got: \(result)")
        XCTAssertTrue(result.contains("Buy groceries"), "Expected text, got: \(result)")
    }

    func testLine_todoPending() {
        let result = NotePreviewHTMLGenerator.parseLine("[ ] Buy groceries")
        XCTAssertFalse(result.contains("todo-done"), "Should not have strikethrough, got: \(result)")
        XCTAssertTrue(result.contains("&#9744;"), "Expected empty checkbox, got: \(result)")
        XCTAssertTrue(result.contains("Buy groceries"), "Expected text, got: \(result)")
    }

    func testLine_fileAttachment() {
        let result = NotePreviewHTMLGenerator.parseLine("[[file|pdf|stored_abc.pdf|report.pdf|medium]]")
        XCTAssertTrue(result.contains("report.pdf"), "Expected original filename, got: \(result)")
        XCTAssertTrue(result.contains("attachment"), "Expected attachment class, got: \(result)")
    }

    func testLine_imageAttachment() {
        let result = NotePreviewHTMLGenerator.parseLine("[[image|||photo.jpg]]")
        XCTAssertTrue(result.contains("attachment"), "Expected attachment class, got: \(result)")
    }

    func testLine_webclip() {
        let result = NotePreviewHTMLGenerator.parseLine("[[webclip|Apple|Apple homepage|https://apple.com]]")
        XCTAssertTrue(result.contains("Apple"), "Expected webclip title, got: \(result)")
        XCTAssertTrue(result.contains("attachment"), "Expected attachment class, got: \(result)")
    }

    func testLine_emptyLine() {
        XCTAssertEqual(NotePreviewHTMLGenerator.parseLine(""), "<br>")
    }

    func testLine_plainText() {
        let result = NotePreviewHTMLGenerator.parseLine("Hello world")
        XCTAssertEqual(result, "<p>Hello world</p>")
    }

    // MARK: - generate

    func testGenerate_containsTitle() {
        let note = Note(title: "My Note", content: "Some content")
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("<h1>My Note</h1>"), "Expected h1 title, got excerpt: \(html.prefix(500))")
    }

    func testGenerate_containsTags() {
        let note = Note(title: "Tagged", content: "", tags: ["work", "urgent"])
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("work"), "Expected tag 'work'")
        XCTAssertTrue(html.contains("urgent"), "Expected tag 'urgent'")
    }

    func testGenerate_escapesTitle() {
        let note = Note(title: "<Script>", content: "")
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertFalse(html.contains("<Script>"), "Raw unescaped tag should not appear")
        XCTAssertTrue(html.contains("&lt;Script&gt;"), "Expected escaped title")
    }

    func testGenerate_rendersBody() {
        let note = Note(title: "Test", content: "[[b]]Bold[[/b]] and normal")
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("<strong>Bold</strong>"), "Expected bold rendering in body")
    }

    func testGenerate_emptyTitleFallback() {
        let note = Note(title: "", content: "")
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("Untitled"), "Empty title should fall back to 'Untitled'")
    }
}
