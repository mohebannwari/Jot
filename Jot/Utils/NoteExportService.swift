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
        let pdfData = NSMutableData()

        // Page dimensions (US Letter)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margins: CGFloat = 72 // 1 inch

        guard let pdfConsumer = CGDataConsumer(data: pdfData),
              let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: nil, nil) else {
            logger.error("buildPDFData: Failed to create PDF context")
            return nil
        }

        for note in notes {
            pdfContext.beginPDFPage(nil)
            pdfContext.saveGState()
            pdfContext.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: pageRect.height))
            let nsGraphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsGraphicsContext

            // Extract image filenames from raw content, convert text to plain readable form
            let (_, imageFilenames) = extractImages(from: note.content)
            let cleanContent = convertMarkupToPlainText(note.content)

            NSColor.white.setFill()
            NSBezierPath(rect: pageRect).fill()

            var yPosition: CGFloat = margins

            // Draw title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            let titleString = NSAttributedString(string: note.title, attributes: titleAttributes)
            let titleRect = CGRect(x: margins, y: yPosition, width: pageRect.width - (margins * 2), height: 100)
            titleString.draw(in: titleRect)
            yPosition += titleString.size().height + 10

            // Draw date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.gray
            ]
            let dateString = NSAttributedString(string: dateFormatter.string(from: note.date), attributes: dateAttributes)
            let dateRect = CGRect(x: margins, y: yPosition, width: pageRect.width - (margins * 2), height: 20)
            dateString.draw(in: dateRect)
            yPosition += dateString.size().height + 10

            // Draw tags
            if !note.tags.isEmpty {
                let tagsString = note.tags.map { "#\($0)" }.joined(separator: " ")
                let tagsAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.systemBlue
                ]
                let tagsAttrString = NSAttributedString(string: tagsString, attributes: tagsAttributes)
                let tagsRect = CGRect(x: margins, y: yPosition, width: pageRect.width - (margins * 2), height: 20)
                tagsAttrString.draw(in: tagsRect)
                yPosition += tagsAttrString.size().height + 20
            }

            // Draw content
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.black
            ]
            let contentString = NSAttributedString(string: cleanContent, attributes: contentAttributes)
            let contentRect = CGRect(x: margins, y: yPosition, width: pageRect.width - (margins * 2), height: pageRect.height - yPosition - margins)
            contentString.draw(in: contentRect)
            yPosition += contentString.boundingRect(with: contentRect.size, options: [.usesLineFragmentOrigin]).height + 20

            // Draw images
            for imageFilename in imageFilenames {
                if let imageURL = ImageStorageManager.shared.getImageURL(for: imageFilename),
                   let image = NSImage(contentsOf: imageURL) {

                    let maxWidth = pageRect.width - (margins * 2)
                    let aspectRatio = image.size.height / image.size.width
                    let imageWidth = min(image.size.width, maxWidth)
                    let imageHeight = imageWidth * aspectRatio

                    if yPosition + imageHeight < pageRect.height - margins {
                        let imageRect = CGRect(
                            x: margins,
                            y: yPosition,
                            width: imageWidth,
                            height: imageHeight
                        )
                        image.draw(in: imageRect)
                        yPosition += imageHeight + 20
                    }
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            pdfContext.restoreGState()
            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return pdfData as Data
    }

    /// Generates a Retina-quality thumbnail image of the first page of a note's PDF representation.
    func generatePreviewImage(for note: Note) async -> NSImage? {
        guard let data = await buildPDFData(notes: [note]),
              let pdfDoc = PDFDocument(data: data),
              let page = pdfDoc.page(at: 0) else { return nil }
        // 2× of 228×337 for Retina sharpness
        return page.thumbnail(of: CGSize(width: 456, height: 674), for: .mediaBox)
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
        generateTextPreviewImage(text, size: CGSize(width: 456, height: 674))
    }

    @MainActor private func generateTextPreviewImage(_ text: String, size: CGSize) -> NSImage? {
        let image = NSImage(size: size)
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
            .foregroundColor: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        (text as NSString).draw(
            in: NSRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2),
            withAttributes: attrs
        )
        image.unlockFocus()
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
        var markdown = ""

        for (index, note) in notes.enumerated() {
            if index > 0 {
                markdown += "\n\n---\n\n"
            }

            markdown += "# \(note.title)\n\n"

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            markdown += "*\(dateFormatter.string(from: note.date))*\n\n"

            if !note.tags.isEmpty {
                markdown += "**Tags:** \(note.tags.map { "#\($0)" }.joined(separator: " "))\n\n"
            }

            markdown += convertMarkupToMarkdown(note.content) + "\n\n"
        }

        return markdown
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
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(NoteMarkupHTMLRenderer.escapeHTML(title))</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 20px;
                    line-height: 1.6;
                    color: #333;
                }
                h1 {
                    color: #000;
                    margin-bottom: 10px;
                }
                .date {
                    color: #666;
                    font-size: 14px;
                    margin-bottom: 20px;
                }
                .tags {
                    margin-bottom: 20px;
                }
                .tag {
                    display: inline-block;
                    background: #e3f2fd;
                    color: #1976d2;
                    padding: 4px 12px;
                    border-radius: 16px;
                    font-size: 14px;
                    margin-right: 8px;
                }
                .content {
                    margin-bottom: 30px;
                }
                hr {
                    border: none;
                    border-top: 1px solid #ddd;
                    margin: 40px 0;
                }
                \(NoteMarkupHTMLRenderer.sharedStyles(for: .export))
            </style>
        </head>
        <body>
        """

        for (index, note) in notes.enumerated() {
            if index > 0 {
                html += "<hr>\n"
            }

            html += "<h1>\(NoteMarkupHTMLRenderer.escapeHTML(note.title))</h1>\n"

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            html += "<div class=\"date\">\(dateFormatter.string(from: note.date))</div>\n"

            if !note.tags.isEmpty {
                html += "<div class=\"tags\">\n"
                for tag in note.tags {
                    html += "<span class=\"tag\">#\(NoteMarkupHTMLRenderer.escapeHTML(tag))</span>\n"
                }
                html += "</div>\n"
            }

            html += "<div class=\"content note-markup\">\(convertMarkupToHTML(note.content))</div>\n"
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
        var result = ""
        for (index, note) in notes.enumerated() {
            if index > 0 { result += "\n\n---\n\n" }
            result += note.title + "\n\n"
            result += convertMarkupToPlainText(note.content)
        }
        return result
    }

    // MARK: - Markup Conversion Engine

    /// Convert serialized [[...]] markup to plain text (strip all formatting)
    func convertMarkupToPlainText(_ content: String) -> String {
        // Strip AI metadata block — it's internal persistence, not user content
        var text = NoteDetailView.stripAIBlock(content).content
        // Strip formatting tag pairs
        let tagPairs = ["b", "i", "u", "s", "h1", "h2", "h3", "code", "ic", "quote"]
        for tag in tagPairs {
            text = text.replacingOccurrences(of: "[[\(tag)]]", with: "")
            text = text.replacingOccurrences(of: "[[/\(tag)]]", with: "")
        }
        // Strip align tags
        if let regex = try? NSRegularExpression(pattern: #"\[\[align:[a-z]+\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/align]]", with: "")
        // Strip color tags
        if let regex = try? NSRegularExpression(pattern: #"\[\[color\|[0-9a-fA-F]{6}\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/color]]", with: "")
        // Strip highlight tags
        if let regex = try? NSRegularExpression(pattern: #"\[\[hl\|[0-9a-fA-F]{6}\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/hl]]", with: "")
        text = text.replacingOccurrences(of: "[[arrow]]", with: "\u{2192}")
        // Convert ordered list prefixes to "N. "
        if let regex = try? NSRegularExpression(pattern: #"\[\[ol\|(\d+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1. ")
        }
        // Convert checkboxes
        text = text.replacingOccurrences(of: "[x] ", with: "[done] ")
        text = text.replacingOccurrences(of: "[ ] ", with: "[todo] ")
        // Convert dividers
        text = text.replacingOccurrences(of: "[[divider]]", with: "---")
        // Convert links (labeled two-pipe form first, then bare single-pipe URL)
        if let regex = try? NSRegularExpression(pattern: #"\[\[link\|([^|\]]+)\|([^\]]+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$2 ($1)")
        }
        if let regex = try? NSRegularExpression(pattern: #"\[\[link\|([^\]]+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }
        // Convert images to placeholder
        if let regex = try? NSRegularExpression(pattern: #"\[\[image\|\|\|[^\]]+\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[Image]")
        }
        if let regex = try? NSRegularExpression(pattern: #"\[\[map\|([^|]*)\|[^\]]+\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[Map: $1]")
        }
        // Convert file attachments to placeholder
        if let regex = try? NSRegularExpression(pattern: #"\[\[file\|[^|]+\|([^|]+)\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[File: $1]")
        }
        // Convert web clips
        if let regex = try? NSRegularExpression(pattern: #"\[\[webclip\|([^|]*)\|([^|]*)\|[^|]*\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$2 ($1)")
        }
        // Convert link cards
        if let regex = try? NSRegularExpression(pattern: #"\[\[linkcard\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1 ($3)")
        }
        // Strip table markup (just show raw cell text)
        if let regex = try? NSRegularExpression(pattern: #"\[\[table\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[Table]")
        }
        return text
    }

    /// Convert serialized [[...]] markup to Markdown
    func convertMarkupToMarkdown(_ content: String) -> String {
        // Strip AI metadata block — it's internal persistence, not user content
        var text = NoteDetailView.stripAIBlock(content).content
        // Headings — must be converted BEFORE stripping inline tags
        text = text.replacingOccurrences(of: "[[h1]]", with: "# ")
        text = text.replacingOccurrences(of: "[[/h1]]", with: "")
        text = text.replacingOccurrences(of: "[[h2]]", with: "## ")
        text = text.replacingOccurrences(of: "[[/h2]]", with: "")
        text = text.replacingOccurrences(of: "[[h3]]", with: "### ")
        text = text.replacingOccurrences(of: "[[/h3]]", with: "")
        // Bold / italic / strikethrough
        text = text.replacingOccurrences(of: "[[b]]", with: "**")
        text = text.replacingOccurrences(of: "[[/b]]", with: "**")
        text = text.replacingOccurrences(of: "[[i]]", with: "*")
        text = text.replacingOccurrences(of: "[[/i]]", with: "*")
        text = text.replacingOccurrences(of: "[[s]]", with: "~~")
        text = text.replacingOccurrences(of: "[[/s]]", with: "~~")
        // Underline has no markdown equivalent — strip
        text = text.replacingOccurrences(of: "[[u]]", with: "")
        text = text.replacingOccurrences(of: "[[/u]]", with: "")
        // Inline code — before block [[code]] (ic is a prefix of code).
        text = text.replacingOccurrences(of: "[[ic]]", with: "`")
        text = text.replacingOccurrences(of: "[[/ic]]", with: "`")
        // Code blocks
        text = text.replacingOccurrences(of: "[[code]]", with: "```\n")
        text = text.replacingOccurrences(of: "[[/code]]", with: "\n```")
        // Block quotes — convert to "> " prefix per line
        text = text.replacingOccurrences(of: "[[quote]]", with: "> ")
        text = text.replacingOccurrences(of: "[[/quote]]", with: "")
        // Figma inline arrow — markdown `-> `.
        text = text.replacingOccurrences(of: "[[arrow]]", with: "-> ")
        // Ordered list prefix
        if let regex = try? NSRegularExpression(pattern: #"\[\[ol\|(\d+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1. ")
        }
        // Checkboxes
        text = text.replacingOccurrences(of: "[x] ", with: "- [x] ")
        text = text.replacingOccurrences(of: "[ ] ", with: "- [ ] ")
        // Dividers
        text = text.replacingOccurrences(of: "[[divider]]", with: "\n---\n")
        // Links — labeled first so single-pipe bare links do not mis-parse.
        if let regex = try? NSRegularExpression(pattern: #"\[\[link\|([^|\]]+)\|([^\]]+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)")
        }
        if let regex = try? NSRegularExpression(pattern: #"\[\[link\|([^\]]+)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$1]($1)")
        }
        // Images
        if let regex = try? NSRegularExpression(pattern: #"\[\[image\|\|\|([^\]|]+)(?:\|\|\|[0-9]*\.?[0-9]+)?\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "![Image]($1)")
        }
        if let regex = try? NSRegularExpression(pattern: #"\[\[map\|([^|]*)\|[^\]]+\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[Map: $1]")
        }
        // File attachments
        if let regex = try? NSRegularExpression(pattern: #"\[\[file\|[^|]+\|([^|]+)\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$1]")
        }
        // Web clips
        if let regex = try? NSRegularExpression(pattern: #"\[\[webclip\|([^|]*)\|([^|]*)\|[^|]*\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)")
        }
        // Link cards
        if let regex = try? NSRegularExpression(pattern: #"\[\[linkcard\|([^|]*)\|([^|]*)\|([^\]]*)\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$1]($3)")
        }
        // Strip alignment (no markdown equivalent)
        if let regex = try? NSRegularExpression(pattern: #"\[\[align:[a-z]+\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/align]]", with: "")
        // Strip color (no markdown equivalent)
        if let regex = try? NSRegularExpression(pattern: #"\[\[color\|[0-9a-fA-F]{6}\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/color]]", with: "")
        // Strip highlight (no markdown equivalent)
        if let regex = try? NSRegularExpression(pattern: #"\[\[hl\|[0-9a-fA-F]{6}\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "[[/hl]]", with: "")
        // Table markup
        if let regex = try? NSRegularExpression(pattern: #"\[\[table\|[^\]]*\]\]"#) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[Table]")
        }
        return text
    }

    /// Convert serialized [[...]] markup to HTML
    func convertMarkupToHTML(_ content: String) -> String {
        NoteMarkupHTMLRenderer.renderFragment(content, context: .export)
    }

    // MARK: - Helper Methods

    /// Extract image references from note content
    /// Returns tuple of (clean content without image tags, array of image filenames)
    private func extractImages(from content: String) -> (String, [String]) {
        let pattern = #"\[\[image\|\|\|([^\]]+)\]\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (content, [])
        }

        var imageFilenames: [String] = []
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))

        for match in matches {
            if let range = Range(match.range(at: 1), in: content) {
                let filename = String(content[range])
                imageFilenames.append(filename)
            }
        }

        // Remove image tags from content
        let cleanContent = regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: NSRange(content.startIndex..., in: content),
            withTemplate: "[Image]"
        )

        return (cleanContent, imageFilenames)
    }

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
