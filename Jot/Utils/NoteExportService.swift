//
//  NoteExportService.swift
//  Jot
//
//  Handles exporting notes to various formats (PDF, Markdown, HTML)
//  with embedded image support.
//

import Foundation
import os
import PDFKit
import UniformTypeIdentifiers
import AppKit
import WebKit

/// Enum representing available export formats for notes
enum NoteExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case markdown = "Markdown"
    case html = "HTML"
    case plainText = "Plain Text"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .html: return "html"
        case .plainText: return "txt"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: return "doc"
        case .markdown: return "doc.text"
        case .html: return "globe"
        case .plainText: return "doc.plaintext"
        }
    }

    var iconAssetName: String {
        switch self {
        case .pdf: return "IconFilePdf"
        case .markdown: return "IconMarkdown"
        case .html: return "IconWebsite"
        case .plainText: return "IconFileText"
        }
    }
}

/// Service responsible for exporting notes to various formats
@MainActor
final class NoteExportService {
    static let shared = NoteExportService()

    private let logger = Logger(subsystem: "com.jot", category: "NoteExportService")

    /// PDF/text thumbnails for `ExportFormatSheet` — ~2× usable sheet width, height matched to PDF page size (`buildPDFDataFromHTML` 612×792) so every format shares the same preview height.
    private enum ExportSheetPreviewBitmap {
        static let width: CGFloat = 666
        private static let pdfPageWidth: CGFloat = 612
        private static let pdfPageHeight: CGFloat = 792
        static var size: CGSize {
            CGSize(width: width, height: width * (pdfPageHeight / pdfPageWidth))
        }
    }

    /// Print overrides applied only when `buildHTMLString` is called with `.pdf` mode.
    /// CSS px ↔ PDF pt is 1:1 in WKWebView's PDF capture, so sizes here are point sizes.
    /// Body lands at ~11.5pt — Word/Pages default body weight on Letter/A4.
    private static let pdfPrintOverrides: String = """
    body.export-pdf .export-note { padding: 72px 72px; }
    body.export-pdf .export-title { font-size: 22px; line-height: 1.2; margin: 0 0 10px; }
    body.export-pdf .date { font-size: 11px; margin-bottom: 14px; }
    body.export-pdf .tag { font-size: 10px; padding: 3px 8px; }
    body.export-pdf .note-markup { font-size: 11.5px; line-height: 1.5; }
    body.export-pdf .note-markup h2 { font-size: 16px; margin: 18px 0 6px; }
    body.export-pdf .note-markup h3 { font-size: 13.5px; margin: 16px 0 6px; }
    body.export-pdf .note-markup h4 { font-size: 12px; margin: 14px 0 6px; }
    body.export-pdf .note-markup p { margin: 0 0 6px; }
    body.export-pdf .note-markup pre { padding: 10px 12px; }
    body.export-pdf .note-markup pre code { font-size: 10.5px; line-height: 1.45; }
    body.export-pdf .note-markup code { font-size: 0.9em; }
    body.export-pdf .note-markup blockquote { margin: 10px 0; }
    body.export-pdf .note-markup .callout { padding: 10px 12px; }
    body.export-pdf .note-markup .callout-label { font-size: 10px; }

    /* Print-friendly overflow: drop horizontal scrollers, force fit-to-page. */
    body.export-pdf .note-markup .table-wrapper,
    body.export-pdf .note-markup .cards-section,
    body.export-pdf .note-markup .tabs-bar,
    body.export-pdf .note-markup .tabs-section { overflow: visible; }
    body.export-pdf .note-markup table { table-layout: auto; min-width: 0 !important; width: 100%; }
    body.export-pdf .note-markup table[style] { min-width: 0 !important; }
    body.export-pdf .note-markup td,
    body.export-pdf .note-markup th { word-break: break-word; overflow-wrap: anywhere; padding: 6px 8px; font-size: 11px; }
    body.export-pdf .note-markup .cards-grid { flex-wrap: wrap; }
    body.export-pdf .note-markup .cards-card { flex: 1 1 220px; }
    body.export-pdf .note-markup .image-block img,
    body.export-pdf .note-markup .file-preview { max-width: 100%; }
    """

    private init() {}

    // MARK: - Public Export Methods

    /// Export a single note to the specified format
    func exportNote(_ note: Note, format: NoteExportFormat) async -> Bool {
        switch format {
        case .pdf:
            return await exportToPDF(notes: [note], filename: sanitizeFilename(note.title))
        case .markdown:
            return await exportToMarkdown(notes: [note], filename: sanitizeFilename(note.title))
        case .html:
            return await exportToHTML(notes: [note], filename: sanitizeFilename(note.title))
        case .plainText:
            return await exportToPlainText(notes: [note], filename: sanitizeFilename(note.title))
        }
    }

    /// Export multiple notes to the specified format
    func exportNotes(_ notes: [Note], format: NoteExportFormat, filename: String = "Notes Export") async -> Bool {
        switch format {
        case .pdf:
            return await exportToPDF(notes: notes, filename: filename)
        case .markdown:
            return await exportToMarkdown(notes: notes, filename: filename)
        case .html:
            return await exportToHTML(notes: notes, filename: filename)
        case .plainText:
            return await exportToPlainText(notes: notes, filename: filename)
        }
    }

    // MARK: - PDF Export

    private func exportToPDF(notes: [Note], filename: String) async -> Bool {
        guard let data = await buildPDFData(notes: notes) else { return false }
        return saveFile(data: data, filename: filename, fileExtension: "pdf")
    }

    /// Builds raw PDF Data for the given notes without triggering a save dialog.
    /// Returns nil if the PDF context could not be created.
    func buildPDFData(notes: [Note]) async -> Data? {
        let html = buildHTMLString(notes: notes, title: exportTitle(for: notes), mode: .pdf)

        do {
            return try await buildPDFDataFromHTML(html)
        } catch {
            logger.error("buildPDFData: Failed to render PDF from HTML: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildPDFDataFromHTML(_ html: String) async throws -> Data {
        // US Letter. Margins live in CSS (.export-pdf .export-note { padding: 72px });
        // the print system gets a zero-margin page so CSS owns the inset.
        let pageSize = NSSize(width: 612, height: 792)

        // Hidden host window. Required: WKWebView must be window-attached for
        // printOperation(with:) to lay out, and runModal(for:) requires a non-nil
        // window. Apple Forum 705138 documents this as the canonical async-safe
        // path — runOperation()/run() hangs against modern WebKit's async render
        // pipeline regardless of thread.
        let hostWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: pageSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.isReleasedWhenClosed = false
        hostWindow.isExcludedFromWindowsMenu = true
        hostWindow.alphaValue = 0
        hostWindow.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))

        let webView = WKWebView(frame: NSRect(origin: .zero, size: pageSize))
        hostWindow.contentView = webView
        // Keeps the window in the window list (needed by the print machinery)
        // without painting pixels anywhere on screen.
        hostWindow.orderOut(nil)

        let loadDelegate = WebViewLoadDelegate()
        webView.navigationDelegate = loadDelegate
        try await loadDelegate.load(html, in: webView)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tempURL as NSURL

        let printOp = webView.printOperation(with: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false
        // Required per Apple Forum 705138 — without this, paginated render can
        // produce blank pages or crash inside the WebContent process.
        printOp.view?.frame = NSRect(origin: .zero, size: pageSize)

        defer {
            hostWindow.contentView = nil
            hostWindow.close()
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let handler = PrintCompletionHandler(cont)
            // Self-retain across the AppKit selector bridge — runModal does not
            // retain its delegate, and the continuation closure returns
            // immediately, so without this the handler is deallocated before
            // the callback fires.
            handler.retainSelf()
            printOp.runModal(
                for: hostWindow,
                delegate: handler,
                didRun: #selector(PrintCompletionHandler.printOperation(_:didRun:contextInfo:)),
                contextInfo: nil
            )
        }

        let data = try Data(contentsOf: tempURL)
        guard !data.isEmpty, (PDFDocument(data: data)?.pageCount ?? 0) > 0 else {
            throw PDFExportError.emptyPDF
        }
        return data
    }

    /// Generates a Retina-quality thumbnail image of the first page of a note's PDF representation.
    func generatePreviewImage(for note: Note) async -> NSImage? {
        guard let data = await buildPDFData(notes: [note]),
              let pdfDoc = PDFDocument(data: data),
              let page = pdfDoc.page(at: 0) else { return nil }
        return page.thumbnail(of: ExportSheetPreviewBitmap.size, for: .mediaBox)
    }

    /// Generates a format-aware preview thumbnail for the export sheet.
    func generatePreviewImage(for note: Note, format: NoteExportFormat) async -> NSImage? {
        switch format {
        case .pdf:
            return await generatePreviewImage(for: note)
        case .markdown:
            return generateTextPreviewImage(buildMarkdownString(notes: [note]))
        case .html:
            return generateTextPreviewImage(buildHTMLString(notes: [note], title: note.title))
        case .plainText:
            return generateTextPreviewImage(buildPlainTextString(notes: [note]))
        }
    }

    /// High-resolution text preview for the Quick Look overlay (~2× standard size).
    @MainActor func generateQuickLookTextImage(_ text: String) -> NSImage? {
        generateTextPreviewImage(text, size: CGSize(width: 1164, height: 1718))
    }

    @MainActor private func generateTextPreviewImage(_ text: String) -> NSImage? {
        generateTextPreviewImage(text, size: ExportSheetPreviewBitmap.size)
    }

    @MainActor private func generateTextPreviewImage(_ text: String, size: CGSize) -> NSImage? {
        let image = NSImage(size: size)
        // Offscreen “paper” preview — resolve label under light appearance so text stays dark on white in dark mode.
        let lightAppearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        lightAppearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            let margin: CGFloat = size.width * 0.05
            let fontSize: CGFloat = size.width * 0.017
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineSpacing = 1
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            (text as NSString).draw(
                in: NSRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2),
                withAttributes: attrs
            )
            image.unlockFocus()
        }
        return image
    }

    // MARK: - Markdown Export

    private func exportToMarkdown(notes: [Note], filename: String) async -> Bool {
        let markdown = buildMarkdownString(notes: notes)
        guard let data = markdown.data(using: .utf8) else {
            logger.error("exportToMarkdown: Failed to convert markdown to data")
            return false
        }
        return saveFile(data: data, filename: filename, fileExtension: "md")
    }

    /// Builds a Markdown string for the given notes without any I/O.
    func buildMarkdownString(notes: [Note]) -> String {
        let documents = notes.map { note in
            var parts: [String] = [
                "# \(markdownEscapedInlineText(note.title))",
                "*\(exportDateString(note.date))*",
            ]

            if !note.tags.isEmpty {
                let tags = note.tags
                    .map { "#\(markdownEscapedInlineText($0))" }
                    .joined(separator: " ")
                parts.append("**Tags:** \(tags)")
            }

            let body = convertMarkupToMarkdown(note.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                parts.append(body)
            }

            return parts.joined(separator: "\n\n")
        }

        return documents.joined(separator: "\n\n---\n\n") + "\n"
    }

    // MARK: - HTML Export

    private func exportToHTML(notes: [Note], filename: String) async -> Bool {
        let html = buildHTMLString(notes: notes, title: filename)
        guard let data = html.data(using: .utf8) else {
            logger.error("exportToHTML: Failed to convert HTML to data")
            return false
        }
        return saveFile(data: data, filename: filename, fileExtension: "html")
    }

    /// Builds an HTML string for the given notes without any I/O.
    func buildHTMLString(notes: [Note], title: String = "Notes") -> String {
        buildHTMLString(notes: notes, title: title, mode: .html)
    }

    private enum HTMLExportMode {
        case html
        case pdf

        var bodyClass: String {
            switch self {
            case .html: return "export-html"
            case .pdf: return "export-pdf"
            }
        }
    }

    private func buildHTMLString(notes: [Note], title: String, mode: HTMLExportMode) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(NoteMarkupHTMLRenderer.escapeHTML(title))</title>
            <style>
                @page {
                    size: 612px 792px;
                    margin: 0;
                }
                * {
                    box-sizing: border-box;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                    line-height: 1.58;
                    color: #1a1a1a;
                    background: #fff;
                    margin: 0;
                    padding: 0;
                    -webkit-print-color-adjust: exact;
                    print-color-adjust: exact;
                }
                body.export-html {
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 20px;
                }
                body.export-pdf {
                    width: 612px;
                    overflow: visible;
                }
                .export-note {
                    break-inside: avoid-page;
                    page-break-inside: avoid;
                }
                .export-pdf .export-note {
                    width: 612px;
                    padding: 56px 64px;
                }
                .export-html .export-note {
                    margin-bottom: 30px;
                }
                .export-note + .export-note {
                    margin-top: 40px;
                }
                .export-pdf .export-note + .export-note {
                    border-top: 1px solid rgba(0, 0, 0, 0.12);
                }
                .export-title {
                    color: #000;
                    font-size: 30px;
                    line-height: 1.15;
                    letter-spacing: 0;
                    margin: 0 0 12px;
                }
                .date {
                    color: rgba(26, 26, 26, 0.62);
                    font-size: 14px;
                    margin-bottom: 16px;
                }
                .tags {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 6px;
                    margin-bottom: 18px;
                }
                .tag {
                    display: inline-block;
                    background: rgba(37, 99, 235, 0.10);
                    color: #2563eb;
                    padding: 4px 10px;
                    border-radius: 999px;
                    font-size: 12px;
                    font-weight: 600;
                }
                .content {
                    margin-top: 0;
                }
                .note-separator {
                    border: none;
                    border-top: 1px solid rgba(0, 0, 0, 0.12);
                    margin: 40px 0;
                }
                .export-pdf .note-separator {
                    display: none;
                }
                .note-markup pre,
                .note-markup table,
                .note-markup blockquote,
                .note-markup .callout,
                .note-markup .code-block,
                .note-markup .image-block,
                .note-markup .cards-card,
                .note-markup .tabs-section {
                    break-inside: avoid-page;
                    page-break-inside: avoid;
                }
                \(NoteMarkupHTMLRenderer.sharedStyles(for: .export))
                \(mode == .pdf ? Self.pdfPrintOverrides : "")
            </style>
        </head>
        <body class="\(mode.bodyClass)">
        """

        for (index, note) in notes.enumerated() {
            if index > 0 {
                html += "<hr class=\"note-separator\">\n"
            }

            html += "<article class=\"export-note\">\n"
            html += "<h1 class=\"export-title\">\(NoteMarkupHTMLRenderer.escapeHTML(note.title))</h1>\n"
            html += "<div class=\"date\">\(NoteMarkupHTMLRenderer.escapeHTML(exportDateString(note.date)))</div>\n"

            if !note.tags.isEmpty {
                html += "<div class=\"tags\">\n"
                for tag in note.tags {
                    html += "<span class=\"tag\">#\(NoteMarkupHTMLRenderer.escapeHTML(tag))</span>\n"
                }
                html += "</div>\n"
            }

            html += "<div class=\"content note-markup\">\(convertMarkupToHTML(note.content))</div>\n"
            html += "</article>\n"
        }

        html += """
        </body>
        </html>
        """

        return html
    }

    // MARK: - Plain Text Export

    private func exportToPlainText(notes: [Note], filename: String) async -> Bool {
        let text = buildPlainTextString(notes: notes)
        guard let data = text.data(using: .utf8) else { return false }
        return saveFile(data: data, filename: filename, fileExtension: "txt")
    }

    func buildPlainTextString(notes: [Note]) -> String {
        let documents = notes.map { note in
            var parts = [note.title, exportDateString(note.date)]
            if !note.tags.isEmpty {
                parts.append("Tags: \(note.tags.map { "#\($0)" }.joined(separator: " "))")
            }
            let body = convertMarkupToPlainText(note.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                parts.append(body)
            }
            return parts.joined(separator: "\n\n")
        }

        return documents.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Markup Conversion Engine

    /// Convert serialized [[...]] markup to plain text (strip all formatting)
    func convertMarkupToPlainText(_ content: String) -> String {
        MarkupTextExporter(format: .plainText).render(content)
    }

    /// Convert serialized [[...]] markup to Markdown
    func convertMarkupToMarkdown(_ content: String) -> String {
        MarkupTextExporter(format: .markdown).render(content)
    }

    /// Convert serialized [[...]] markup to HTML
    func convertMarkupToHTML(_ content: String) -> String {
        NoteMarkupHTMLRenderer.renderFragment(content, context: .export)
    }

    private func exportTitle(for notes: [Note]) -> String {
        if notes.count == 1, let title = notes.first?.title, !title.isEmpty {
            return title
        }
        return "Notes Export"
    }

    private func exportDateString(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }

    private func markdownEscapedInlineText(_ text: String) -> String {
        Self.markdownEscapedInlineText(text)
    }

    private static func markdownEscapedInlineText(_ text: String) -> String {
        JotMarkupLiteral.replacingRawTokens(in: text)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private struct MarkupTextExporter {
        enum Format {
            case markdown
            case plainText
        }

        let format: Format

        func render(_ content: String) -> String {
            let source = NoteDetailView.stripAIBlock(content).content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return renderBlocks(source).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func renderBlocks(_ content: String) -> String {
            guard !content.isEmpty else { return "" }

            let lines = content.components(separatedBy: "\n")
            var index = 0
            var output: [String] = []

            func append(_ block: String) {
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    if output.last != "" {
                        output.append("")
                    }
                    return
                }
                output.append(trimmed)
            }

            while index < lines.count {
                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[codeblock|",
                    closeMarker: "[[/codeblock]]"
                ) {
                    append(renderCodeBlock(block.blockText))
                    index = block.nextIndex
                    continue
                }

                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[code]]",
                    closeMarker: "[[/code]]"
                ) {
                    append(renderLegacyCodeBlock(block.blockText))
                    index = block.nextIndex
                    continue
                }

                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[table|",
                    closeMarker: "[[/table]]"
                ) {
                    append(renderTable(block.blockText))
                    index = block.nextIndex
                    continue
                }

                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[callout|",
                    closeMarker: "[[/callout]]"
                ) {
                    append(renderCallout(block.blockText))
                    index = block.nextIndex
                    continue
                }

                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[cards|",
                    closeMarker: "[[/cards]]"
                ) {
                    append(renderCards(block.blockText))
                    index = block.nextIndex
                    continue
                }

                if let block = gatherDelimitedBlock(
                    from: lines,
                    start: index,
                    openPrefix: "[[tabs|",
                    closeMarker: "[[/tabs]]"
                ) {
                    append(renderTabs(block.blockText))
                    index = block.nextIndex
                    continue
                }

                append(renderLine(lines[index]))
                index += 1
            }

            return output
                .joined(separator: "\n")
                .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        }

        private func renderLine(_ rawLine: String) -> String {
            let (line, _) = unwrapAlignment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard !trimmed.isEmpty else { return "" }

            if trimmed == "[[divider]]" {
                return "---"
            }

            if line.hasPrefix("[[quote]]"), line.hasSuffix("[[/quote]]") {
                let inner = String(line.dropFirst(9).dropLast(10))
                let body = renderInline(inner)
                return format == .markdown ? "> \(body)" : body
            }

            if let heading = renderHeading(line) {
                return heading
            }

            if let list = renderListLine(line) {
                return list
            }

            return renderInline(line)
        }

        private func renderHeading(_ line: String) -> String? {
            let mappings: [(String, String, String)] = [
                ("[[h1]]", "[[/h1]]", format == .markdown ? "## " : ""),
                ("[[h2]]", "[[/h2]]", format == .markdown ? "### " : ""),
                ("[[h3]]", "[[/h3]]", format == .markdown ? "#### " : ""),
            ]

            for (open, close, prefix) in mappings where line.hasPrefix(open) && line.hasSuffix(close) {
                let innerStart = line.index(line.startIndex, offsetBy: open.count)
                let innerEnd = line.index(line.endIndex, offsetBy: -close.count)
                return prefix + renderInline(String(line[innerStart..<innerEnd]))
            }

            return nil
        }

        private func renderListLine(_ line: String) -> String? {
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let indentWidth = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            let indent = String(repeating: " ", count: format == .markdown ? indentWidth : 0)
            let stripped = String(line.dropFirst(leading.count))

            if stripped.hasPrefix("[x] ") {
                let body = renderInline(String(stripped.dropFirst(4)))
                return format == .markdown ? "\(indent)- [x] \(body)" : "[done] \(body)"
            }
            if stripped == "[x]" {
                return format == .markdown ? "\(indent)- [x]" : "[done]"
            }
            if stripped.hasPrefix("[ ] ") {
                let body = renderInline(String(stripped.dropFirst(4)))
                return format == .markdown ? "\(indent)- [ ] \(body)" : "[todo] \(body)"
            }
            if stripped == "[ ]" {
                return format == .markdown ? "\(indent)- [ ]" : "[todo]"
            }

            for marker in ["• ", "- ", "* ", "+ "] where stripped.hasPrefix(marker) {
                let body = renderInline(String(stripped.dropFirst(2)))
                return format == .markdown ? "\(indent)- \(body)" : "- \(body)"
            }

            if stripped.hasPrefix("[[ol|"), let closeRange = stripped.range(of: "]]") {
                let numberStart = stripped.index(stripped.startIndex, offsetBy: 5)
                let number = String(stripped[numberStart..<closeRange.lowerBound])
                let body = renderInline(String(stripped[closeRange.upperBound...]))
                return "\(indent)\(number). \(body)"
            }

            return nil
        }

        private func renderCodeBlock(_ blockText: String) -> String {
            guard let codeBlock = CodeBlockData.deserialize(from: blockText) else {
                return format == .markdown ? "```text\nUnsupported code block\n```" : "Unsupported code block"
            }

            switch format {
            case .markdown:
                let language = codeBlock.language == "plaintext" ? "" : codeBlock.language
                let fence = codeFence(for: codeBlock.code)
                return "\(fence)\(language)\n\(codeBlock.code)\n\(fence)"
            case .plainText:
                return codeBlock.code
            }
        }

        private func renderLegacyCodeBlock(_ blockText: String) -> String {
            guard let openRange = blockText.range(of: "[[code]]"),
                  let closeRange = blockText.range(of: "[[/code]]") else {
                return ""
            }
            let code = String(blockText[openRange.upperBound..<closeRange.lowerBound])
            switch format {
            case .markdown:
                let fence = codeFence(for: code)
                return "\(fence)\n\(code)\n\(fence)"
            case .plainText:
                return code
            }
        }

        private func renderTable(_ blockText: String) -> String {
            guard let table = NoteTableData.deserialize(from: blockText) else {
                return format == .markdown ? "[Unsupported table]" : "Unsupported table"
            }

            switch format {
            case .markdown:
                let rows = table.cells
                guard let header = rows.first else { return "" }
                let headerLine = markdownTableRow(header)
                let divider = "| " + Array(repeating: "---", count: max(1, table.columns)).joined(separator: " | ") + " |"
                let body = rows.dropFirst().map(markdownTableRow).joined(separator: "\n")
                return [headerLine, divider, body]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            case .plainText:
                return table.cells
                    .map { row in row.map(plainTableCell).joined(separator: "\t") }
                    .joined(separator: "\n")
            }
        }

        private func markdownTableRow(_ row: [String]) -> String {
            "| " + row.map(markdownTableCell).joined(separator: " | ") + " |"
        }

        private func markdownTableCell(_ value: String) -> String {
            let decoded = JotMarkupLiteral.replacingRawTokens(in: value)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: "<br>")
            return decoded.isEmpty ? " " : decoded
        }

        private func plainTableCell(_ value: String) -> String {
            JotMarkupLiteral.replacingRawTokens(in: value)
                .replacingOccurrences(of: "\n", with: " / ")
        }

        private func renderCallout(_ blockText: String) -> String {
            guard let callout = CalloutData.deserialize(from: blockText) else {
                return format == .markdown ? "> [!note]\n> Unsupported callout" : "Unsupported callout"
            }

            let body = renderBlocks(callout.content)
            switch format {
            case .markdown:
                let prefix = "> [!\(callout.type.rawValue)]"
                let bodyLines = body.components(separatedBy: "\n").map { line in
                    line.isEmpty ? ">" : "> \(line)"
                }
                return ([prefix] + bodyLines).joined(separator: "\n")
            case .plainText:
                return "\(callout.type.rawValue.capitalized)\n\(body)"
            }
        }

        private func renderCards(_ blockText: String) -> String {
            guard let cards = CardSectionData.deserialize(from: blockText) else {
                return format == .markdown ? "[Unsupported cards]" : "Unsupported cards"
            }

            var rendered: [String] = []
            for (columnIndex, column) in cards.columns.enumerated() {
                for (cardIndex, card) in column.enumerated() {
                    let title = "Card \(columnIndex + 1).\(cardIndex + 1)"
                    let body = renderBlocks(card.content)
                    switch format {
                    case .markdown:
                        rendered.append("#### \(title)\n\(body)")
                    case .plainText:
                        rendered.append("\(title)\n\(body)")
                    }
                }
            }
            return rendered.joined(separator: "\n\n")
        }

        private func renderTabs(_ blockText: String) -> String {
            guard let tabs = TabsContainerData.deserialize(from: blockText) else {
                return format == .markdown ? "[Unsupported tabs]" : "Unsupported tabs"
            }

            return tabs.panes.map { pane in
                let body = renderBlocks(pane.content)
                switch format {
                case .markdown:
                    return "#### Tab: \(Self.markdownEscapedInlineText(pane.name))\n\(body)"
                case .plainText:
                    return "Tab: \(pane.name)\n\(body)"
                }
            }
            .joined(separator: "\n\n")
        }

        private func renderInline(_ text: String) -> String {
            guard !text.isEmpty else { return "" }

            var output = ""
            var index = text.startIndex

            while index < text.endIndex {
                let remaining = text[index...]

                if let literal = JotMarkupLiteral.consumeToken(in: text, at: index) {
                    output += escapedText(literal.decoded)
                    index = literal.end
                    continue
                }

                if remaining.hasPrefix("[[b]]") {
                    output += format == .markdown ? "**" : ""
                    index = text.index(index, offsetBy: 5)
                    continue
                }
                if remaining.hasPrefix("[[/b]]") {
                    output += format == .markdown ? "**" : ""
                    index = text.index(index, offsetBy: 6)
                    continue
                }
                if remaining.hasPrefix("[[i]]") {
                    output += format == .markdown ? "*" : ""
                    index = text.index(index, offsetBy: 5)
                    continue
                }
                if remaining.hasPrefix("[[/i]]") {
                    output += format == .markdown ? "*" : ""
                    index = text.index(index, offsetBy: 6)
                    continue
                }
                if remaining.hasPrefix("[[s]]") {
                    output += format == .markdown ? "~~" : ""
                    index = text.index(index, offsetBy: 5)
                    continue
                }
                if remaining.hasPrefix("[[/s]]") {
                    output += format == .markdown ? "~~" : ""
                    index = text.index(index, offsetBy: 6)
                    continue
                }
                if remaining.hasPrefix("[[u]]") {
                    index = text.index(index, offsetBy: 5)
                    continue
                }
                if remaining.hasPrefix("[[/u]]") {
                    index = text.index(index, offsetBy: 6)
                    continue
                }
                if remaining.hasPrefix("[[ic]]") {
                    let contentStart = text.index(index, offsetBy: 6)
                    if let close = text[contentStart...].range(of: "[[/ic]]") {
                        let inner = JotMarkupLiteral.replacingRawTokens(in: String(text[contentStart..<close.lowerBound]))
                        output += format == .markdown ? markdownCodeSpan(inner) : inner
                        index = close.upperBound
                    } else {
                        output += escapedText("[[ic]]")
                        index = contentStart
                    }
                    continue
                }
                if remaining.hasPrefix("[[/ic]]") {
                    output += escapedText("[[/ic]]")
                    index = text.index(index, offsetBy: 7)
                    continue
                }
                if remaining.hasPrefix("[[arrow]]") {
                    output += format == .markdown ? "->" : "\u{2192}"
                    index = text.index(index, offsetBy: 9)
                    continue
                }
                if remaining.hasPrefix("[[color|"), let close = remaining.range(of: "]]") {
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[/color]]") {
                    index = text.index(index, offsetBy: 10)
                    continue
                }
                if remaining.hasPrefix("[[hl|"), let close = remaining.range(of: "]]") {
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[/hl]]") {
                    index = text.index(index, offsetBy: 7)
                    continue
                }
                if remaining.hasPrefix("[[link|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 7)..<close.lowerBound])
                    output += renderLinkToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[notelink|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 11)..<close.lowerBound])
                    output += renderNoteLinkToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[webclip|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 10)..<close.lowerBound])
                    output += renderWebClipToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[linkcard|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 11)..<close.lowerBound])
                    output += renderLinkCardToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[filelink|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 11)..<close.lowerBound])
                    output += renderFileLinkToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[file|"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 7)..<close.lowerBound])
                    output += renderFileToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[[image|||"), let close = remaining.range(of: "]]") {
                    let body = String(remaining[remaining.index(remaining.startIndex, offsetBy: 10)..<close.lowerBound])
                    output += renderImageToken(body)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix(MapBlockData.markupPrefix), let close = remaining.range(of: "]]") {
                    let token = String(remaining[..<close.upperBound])
                    output += renderMapToken(token)
                    index = close.upperBound
                    continue
                }
                if remaining.hasPrefix("[["), let close = remaining.range(of: "]]") {
                    let tokenBody = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<close.lowerBound])
                    output += escapedText(tokenBody)
                    index = close.upperBound
                    continue
                }

                output += escapedText(String(text[index]))
                index = text.index(after: index)
            }

            return output
        }

        private func renderLinkToken(_ body: String) -> String {
            let parts = body.components(separatedBy: "|")
            guard let rawURL = parts.first else { return "" }
            let label = parts.count > 1 ? parts[1] : rawURL
            switch format {
            case .markdown:
                return "[\(Self.markdownEscapedInlineText(label))](\(markdownURL(rawURL)))"
            case .plainText:
                return parts.count > 1 ? "\(label) (\(rawURL))" : rawURL
            }
        }

        private func renderNoteLinkToken(_ body: String) -> String {
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let title = parts.count == 2 ? String(parts[1]) : "Mentioned Note"
            return format == .markdown ? "@\(Self.markdownEscapedInlineText(title))" : "@\(title)"
        }

        private func renderWebClipToken(_ body: String) -> String {
            let parts = body.components(separatedBy: "|")
            let title = parts.first(where: { !$0.isEmpty }) ?? "Web Clip"
            let url = parts.count >= 3 ? parts[2] : (parts.last ?? "#")
            return format == .markdown
                ? "[\(Self.markdownEscapedInlineText(title))](\(markdownURL(url)))"
                : "\(title) (\(url))"
        }

        private func renderLinkCardToken(_ body: String) -> String {
            let parts = body.components(separatedBy: "|")
            let title = parts.first(where: { !$0.isEmpty }) ?? "Link"
            let url = parts.count >= 3 ? parts[2] : (parts.last ?? "#")
            return format == .markdown
                ? "[\(Self.markdownEscapedInlineText(title))](\(markdownURL(url)))"
                : "\(title) (\(url))"
        }

        private func renderFileLinkToken(_ body: String) -> String {
            let parts = body.components(separatedBy: "|")
            let displayName = parts.count >= 2 ? parts[1] : (parts.first ?? "File")
            return format == .markdown ? "[\(Self.markdownEscapedInlineText(displayName))]" : "[File: \(displayName)]"
        }

        private func renderFileToken(_ body: String) -> String {
            let parts = body.components(separatedBy: "|")
            let originalName: String
            if parts.count >= 3 {
                originalName = parts[2]
            } else if let fallback = parts.last {
                originalName = fallback
            } else {
                originalName = "File"
            }
            return format == .markdown ? "[\(Self.markdownEscapedInlineText(originalName))]" : "[File: \(originalName)]"
        }

        private func renderImageToken(_ body: String) -> String {
            let filename = body.components(separatedBy: "|||").first ?? ""
            return format == .markdown
                ? "![Image](\(markdownURL(filename)))"
                : "[Image: \(filename.isEmpty ? "Image" : filename)]"
        }

        private func renderMapToken(_ token: String) -> String {
            let title = MapBlockData.deserialize(from: token)?.displayTitle ?? "Map"
            return format == .markdown ? "[Map: \(Self.markdownEscapedInlineText(title))]" : "[Map: \(title)]"
        }

        private func escapedText(_ text: String) -> String {
            switch format {
            case .markdown:
                return Self.markdownEscapedInlineText(text)
            case .plainText:
                return JotMarkupLiteral.replacingRawTokens(in: text)
            }
        }

        private func markdownCodeSpan(_ text: String) -> String {
            let longestRun = longestBacktickRun(in: text)
            let delimiter = String(repeating: "`", count: max(1, longestRun + 1))
            if text.hasPrefix("`") || text.hasSuffix("`") || text.contains("\n") {
                return "\(delimiter) \(text) \(delimiter)"
            }
            return "\(delimiter)\(text)\(delimiter)"
        }

        private func codeFence(for code: String) -> String {
            String(repeating: "`", count: max(3, longestBacktickRun(in: code) + 1))
        }

        private func longestBacktickRun(in text: String) -> Int {
            var longest = 0
            var current = 0
            for character in text {
                if character == "`" {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            return longest
        }

        private func markdownURL(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "%20")
                .replacingOccurrences(of: ")", with: "%29")
        }

        private static func markdownEscapedInlineText(_ text: String) -> String {
            NoteExportService.markdownEscapedInlineText(text)
        }

        private func unwrapAlignment(_ line: String) -> (String, String?) {
            let prefixes = ["[[align:center]]", "[[align:right]]", "[[align:justify]]"]
            for prefix in prefixes where line.hasPrefix(prefix) {
                var body = String(line.dropFirst(prefix.count))
                if body.hasSuffix("[[/align]]") {
                    body.removeLast("[[/align]]".count)
                }
                return (body, prefix)
            }
            return (line, nil)
        }

        private func gatherDelimitedBlock(
            from lines: [String],
            start: Int,
            openPrefix: String,
            closeMarker: String
        ) -> (blockText: String, nextIndex: Int)? {
            let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(openPrefix) else { return nil }

            var collected: [String] = []
            var index = start
            while index < lines.count {
                collected.append(lines[index])
                if lines[index].contains(closeMarker) {
                    return (collected.joined(separator: "\n"), index + 1)
                }
                index += 1
            }
            return nil
        }
    }

    // MARK: - Helper Methods

    /// Save file using NSSavePanel — always called on main thread
    @MainActor
    private func saveFile(data: Data, filename: String, fileExtension: String) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Note"
        savePanel.message = "Choose where to save the exported file"
        savePanel.nameFieldStringValue = "\(filename).\(fileExtension)"
        if let contentType = UTType(filenameExtension: fileExtension) {
            savePanel.allowedContentTypes = [contentType]
        } else if let fallbackType = UTType(filenameExtension: fileExtension, conformingTo: .data) {
            savePanel.allowedContentTypes = [fallbackType]
        }
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let response = savePanel.runModal()

        guard response == .OK, let url = savePanel.url else {
            return false
        }

        do {
            try data.write(to: url)
            return true
        } catch {
            logger.error("saveFile: Failed to write file: \(error.localizedDescription)")
            return false
        }
    }

    /// Sanitize filename by removing invalid characters
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "-")
    }
}

private enum PDFExportError: LocalizedError {
    case emptyPDF
    case printFailed

    var errorDescription: String? {
        switch self {
        case .emptyPDF:
            return "WebKit returned an empty PDF document."
        case .printFailed:
            return "WebKit's print operation did not complete successfully."
        }
    }
}

/// Bridges `NSPrintOperation.runModal(for:delegate:didRun:contextInfo:)`'s
/// Objective-C completion selector into a Swift `CheckedContinuation`.
/// Self-retains across the AppKit bridge — `runModal` does not retain delegates.
@MainActor
private final class PrintCompletionHandler: NSObject {
    private let continuation: CheckedContinuation<Void, Error>
    private var selfRef: PrintCompletionHandler?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        super.init()
    }

    func retainSelf() {
        self.selfRef = self
    }

    @objc func printOperation(
        _ printOperation: Any,
        didRun success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if success {
            continuation.resume()
        } else {
            continuation.resume(throwing: PDFExportError.printFailed)
        }
        selfRef = nil
    }
}

@MainActor
private final class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        resume(throwing: error)
    }

    private func resume(throwing error: (any Error)? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
