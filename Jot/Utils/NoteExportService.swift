//
//  NoteExportService.swift
//  Jot
//
//  Handles exporting notes to various formats (PDF, Markdown, HTML)
//  with embedded image support.
//

import Foundation
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Enum representing available export formats for notes
enum NoteExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case markdown = "Markdown"
    case html = "HTML"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .html: return "html"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: return "doc"
        case .markdown: return "doc.text"
        case .html: return "globe"
        }
    }
}

/// Service responsible for exporting notes to various formats
@MainActor
final class NoteExportService {
    static let shared = NoteExportService()

    private init() {}

    // MARK: - Public Export Methods

    /// Export a single note to the specified format
    func exportNote(_ note: Note, format: NoteExportFormat) async -> Bool {
        NSLog("NoteExportService: Exporting note '%@' to %@", note.title, format.rawValue)

        switch format {
        case .pdf:
            return await exportToPDF(notes: [note], filename: sanitizeFilename(note.title))
        case .markdown:
            return await exportToMarkdown(notes: [note], filename: sanitizeFilename(note.title))
        case .html:
            return await exportToHTML(notes: [note], filename: sanitizeFilename(note.title))
        }
    }

    /// Export multiple notes to the specified format
    func exportNotes(_ notes: [Note], format: NoteExportFormat, filename: String = "Notes Export") async -> Bool {
        NSLog("NoteExportService: Batch exporting %d notes to %@", notes.count, format.rawValue)

        switch format {
        case .pdf:
            return await exportToPDF(notes: notes, filename: filename)
        case .markdown:
            return await exportToMarkdown(notes: notes, filename: filename)
        case .html:
            return await exportToHTML(notes: notes, filename: filename)
        }
    }

    // MARK: - PDF Export

    private func exportToPDF(notes: [Note], filename: String) async -> Bool {
        #if os(macOS)
        // Create PDF data
        let pdfData = NSMutableData()

        // Page dimensions (US Letter)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margins: CGFloat = 72 // 1 inch

        // Create PDF context
        guard let pdfConsumer = CGDataConsumer(data: pdfData),
              let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: nil, nil) else {
            NSLog("NoteExportService: Failed to create PDF context")
            return false
        }

        // Draw each note as a page
        for note in notes {
            // Begin page
            pdfContext.beginPDFPage(nil)

            // Create graphics context
            let nsGraphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsGraphicsContext

            // Extract images from content
            let (cleanContent, imageFilenames) = extractImages(from: note.content)

            // Draw white background
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

                    // Check if we have space on current page
                    let maxWidth = pageRect.width - (margins * 2)
                    let aspectRatio = image.size.height / image.size.width
                    let imageWidth = min(image.size.width, maxWidth)
                    let imageHeight = imageWidth * aspectRatio

                    // If image doesn't fit, we'll just clip it for now
                    // In a more advanced version, we'd create a new page
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

            // End page
            pdfContext.endPDFPage()
        }

        // Close PDF
        pdfContext.closePDF()

        return saveFile(data: pdfData as Data, filename: filename, fileExtension: "pdf")
        #else
        NSLog("NoteExportService: PDF export not supported on iOS")
        return false
        #endif
    }

    // MARK: - Markdown Export

    private func exportToMarkdown(notes: [Note], filename: String) async -> Bool {
        var markdown = ""

        for (index, note) in notes.enumerated() {
            if index > 0 {
                markdown += "\n\n---\n\n"
            }

            // Add title
            markdown += "# \(note.title)\n\n"

            // Add date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            markdown += "*\(dateFormatter.string(from: note.date))*\n\n"

            // Add tags
            if !note.tags.isEmpty {
                markdown += "**Tags:** \(note.tags.map { "#\($0)" }.joined(separator: " "))\n\n"
            }

            // Extract images and replace with markdown syntax
            let (cleanContent, imageFilenames) = extractImages(from: note.content)
            markdown += cleanContent + "\n\n"

            // Add images as markdown image references
            for imageFilename in imageFilenames {
                if ImageStorageManager.shared.getImageURL(for: imageFilename) != nil {
                    markdown += "![Image](\(imageFilename))\n\n"
                }
            }
        }

        guard let data = markdown.data(using: .utf8) else {
            NSLog("NoteExportService: Failed to convert markdown to data")
            return false
        }

        return saveFile(data: data, filename: filename, fileExtension: "md")
    }

    // MARK: - HTML Export

    private func exportToHTML(notes: [Note], filename: String) async -> Bool {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(filename)</title>
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
                    white-space: pre-wrap;
                    margin-bottom: 30px;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 20px 0;
                }
                hr {
                    border: none;
                    border-top: 1px solid #ddd;
                    margin: 40px 0;
                }
            </style>
        </head>
        <body>
        """

        for (index, note) in notes.enumerated() {
            if index > 0 {
                html += "<hr>\n"
            }

            html += "<h1>\(escapeHTML(note.title))</h1>\n"

            // Add date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            html += "<div class=\"date\">\(dateFormatter.string(from: note.date))</div>\n"

            // Add tags
            if !note.tags.isEmpty {
                html += "<div class=\"tags\">\n"
                for tag in note.tags {
                    html += "<span class=\"tag\">#\(escapeHTML(tag))</span>\n"
                }
                html += "</div>\n"
            }

            // Extract images and replace with HTML
            let (cleanContent, imageFilenames) = extractImages(from: note.content)
            html += "<div class=\"content\">\(escapeHTML(cleanContent))</div>\n"

            // Add images as base64 embedded images
            for imageFilename in imageFilenames {
                if let imageURL = ImageStorageManager.shared.getImageURL(for: imageFilename),
                   let imageData = try? Data(contentsOf: imageURL) {
                    let base64String = imageData.base64EncodedString()
                    let mimeType = "image/jpeg" // Assuming JPEG as that's what ImageStorageManager saves
                    html += "<img src=\"data:\(mimeType);base64,\(base64String)\" alt=\"Image\">\n"
                }
            }
        }

        html += """
        </body>
        </html>
        """

        guard let data = html.data(using: .utf8) else {
            NSLog("NoteExportService: Failed to convert HTML to data")
            return false
        }

        return saveFile(data: data, filename: filename, fileExtension: "html")
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

    /// Save file using NSSavePanel
    /// CRITICAL: This must be called from a synchronous context to allow runModal() to work
    private nonisolated func saveFile(data: Data, filename: String, fileExtension: String) -> Bool {
        #if os(macOS)
        // runModal() MUST run on the main thread in a synchronous context
        // We use DispatchQueue.main.sync to escape the async context
        var result = false

        // If already on main thread, execute directly. Otherwise use sync dispatch.
        if Thread.isMainThread {
            result = saveFileOnMainThread(data: data, filename: filename, fileExtension: fileExtension)
        } else {
            DispatchQueue.main.sync {
                result = saveFileOnMainThread(data: data, filename: filename, fileExtension: fileExtension)
            }
        }

        return result
        #else
        NSLog("NoteExportService: File saving not supported on iOS")
        return false
        #endif
    }

    #if os(macOS)
    /// Helper to run save panel on main thread
    private nonisolated func saveFileOnMainThread(data: Data, filename: String, fileExtension: String) -> Bool {
        NSLog("NoteExportService: Starting save file dialog for %@.%@", filename, fileExtension)

        let savePanel = NSSavePanel()
        savePanel.title = "Export Note"
        savePanel.message = "Choose where to save the exported file"
        savePanel.nameFieldStringValue = "\(filename).\(fileExtension)"
        if let contentType = UTType(filenameExtension: fileExtension) {
            savePanel.allowedContentTypes = [contentType]
        } else {
            // Fallback for unexpected extensions
            savePanel.allowedFileTypes = [fileExtension]
        }
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        NSLog("NoteExportService: Presenting save panel")

        let response = savePanel.runModal()
        NSLog("NoteExportService: Save panel response: %@", response == .OK ? "OK" : "Cancel")

        guard response == .OK, let url = savePanel.url else {
            NSLog("NoteExportService: User cancelled save or no URL provided")
            return false
        }

        do {
            try data.write(to: url)
            NSLog("NoteExportService: Successfully saved file to %@", url.path)
            return true
        } catch {
            NSLog("NoteExportService: Failed to write file: %@", error.localizedDescription)
            return false
        }
    }
    #endif

    /// Sanitize filename by removing invalid characters
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    /// Escape HTML special characters
    private func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
