//
//  NoteImportService.swift
//  Jot
//
//  Handles importing notes from various file formats (PDF, Markdown, HTML,
//  TXT, RTF, DOCX) with conversion to the app's custom markup format.
//

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Supported import file formats
enum NoteImportFormat: String, CaseIterable {
    case pdf, markdown, html, txt, rtf, docx, csv

    var fileExtensions: [String] {
        switch self {
        case .pdf: return ["pdf"]
        case .markdown: return ["md", "markdown"]
        case .html: return ["html", "htm"]
        case .txt: return ["txt", "text"]
        case .rtf: return ["rtf"]
        case .docx: return ["docx"]
        case .csv: return ["csv"]
        }
    }

    var utTypes: [UTType] {
        switch self {
        case .pdf: return [.pdf]
        case .markdown: return [UTType(filenameExtension: "md") ?? .plainText]
        case .html: return [.html]
        case .txt: return [.plainText]
        case .rtf: return [.rtf]
        case .docx: return [UTType(filenameExtension: "docx") ?? .data]
        case .csv: return [.commaSeparatedText]
        }
    }

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .txt: return "Plain Text"
        case .rtf: return "Rich Text"
        case .docx: return "Word Document"
        case .csv: return "CSV"
        }
    }

    /// Detect format from file extension
    static func from(url: URL) -> NoteImportFormat? {
        let ext = url.pathExtension.lowercased()
        return allCases.first { $0.fileExtensions.contains(ext) }
    }

    /// Union of all supported UTTypes for NSOpenPanel filtering
    static var allSupportedUTTypes: [UTType] {
        allCases.flatMap(\.utTypes)
    }
}

/// Service responsible for importing notes from external files
@MainActor
final class NoteImportService {
    static let shared = NoteImportService()
    private init() {}

    // MARK: - Public API

    /// Import a single file, returning the created Note
    func importFile(
        at url: URL,
        into manager: SimpleSwiftDataManager,
        folderID: UUID? = nil
    ) async -> Note? {
        guard let format = NoteImportFormat.from(url: url) else { return nil }

        let result: (title: String, content: String)?

        switch format {
        case .txt:      result = convertTXT(at: url)
        case .markdown: result = await convertMarkdown(at: url)
        case .html:     result = await convertHTML(at: url)
        case .rtf:      result = await convertRTF(at: url)
        case .docx:     result = await convertDOCX(at: url)
        case .pdf:      result = await convertPDF(at: url)
        case .csv:      result = convertCSV(at: url)
        }

        guard let (title, content) = result else { return nil }
        return manager.addNote(title: title, content: content, folderID: folderID)
    }

    /// Import multiple files with optional progress callback
    func importFiles(
        at urls: [URL],
        into manager: SimpleSwiftDataManager,
        folderID: UUID? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> [Note] {
        var notes: [Note] = []
        for (index, url) in urls.enumerated() {
            onProgress?(index + 1, urls.count, url.lastPathComponent)
            if let note = await importFile(at: url, into: manager, folderID: folderID) {
                notes.append(note)
            }
        }
        return notes
    }

    /// Present NSOpenPanel and import selected files
    func presentImportPanel(
        into manager: SimpleSwiftDataManager,
        folderID: UUID? = nil,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> [Note] {
        let panel = NSOpenPanel()
        panel.title = "Import Notes"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = NoteImportFormat.allSupportedUTTypes

        let response = panel.runModal()
        guard response == .OK else { return [] }

        return await importFiles(
            at: panel.urls,
            into: manager,
            folderID: folderID,
            onProgress: onProgress
        )
    }

    // MARK: - Converters

    private func convertTXT(at url: URL) -> (title: String, content: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (titleFromURL(url), text)
    }

    private func convertMarkdown(at url: URL) async -> (title: String, content: String)? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let baseDir = url.deletingLastPathComponent()
        var lines: [String] = []
        var insideCodeBlock = false
        var pendingTableRows: [[String]] = []

        /// Flush accumulated pipe-table rows into a [[table|...]] block
        func flushPipeTable() {
            guard !pendingTableRows.isEmpty else { return }
            let maxCols = pendingTableRows.map(\.count).max() ?? 1
            let normalized = pendingTableRows.map { row in
                row + Array(repeating: "", count: max(0, maxCols - row.count))
            }
            let tableData = NoteTableData(columns: maxCols, cells: normalized, columnWidths: Array(repeating: NoteTableData.defaultColumnWidth, count: maxCols))
            lines.append(tableData.serialize())
            pendingTableRows.removeAll()
        }

        for line in raw.components(separatedBy: .newlines) {
            // Code fences — toggle tracking, strip markers
            if line.hasPrefix("```") {
                flushPipeTable()
                insideCodeBlock.toggle()
                continue
            }
            if insideCodeBlock {
                lines.append(line)
                continue
            }

            // Pipe-delimited markdown table detection
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                // Check if this is a separator row (e.g. |---|---|)
                let inner = trimmed.dropFirst().dropLast()
                let isSeparator = inner.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
                if isSeparator && inner.contains("-") {
                    // Skip separator rows, they don't carry data
                    continue
                }
                // Parse cells from pipe-delimited row
                let cells = inner.components(separatedBy: "|").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                pendingTableRows.append(cells)
                continue
            } else {
                // Non-table line — flush any accumulated table
                flushPipeTable()
            }

            var converted = line
            var blockPrefix = ""
            var blockSuffix = ""

            // Horizontal rules: ---, ***, ___
            let hrTrimmed = converted.trimmingCharacters(in: .whitespaces)
            if hrTrimmed.count >= 3,
               hrTrimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }),
               Set(hrTrimmed).count == 1
            {
                lines.append("")
                continue
            }

            // Block quotes: > text (strip prefix, wrap later)
            if converted.hasPrefix("> ") {
                converted = String(converted.dropFirst(2))
                blockPrefix = "[[quote]]"
                blockSuffix = "[[/quote]]"
            } else if converted == ">" {
                lines.append("[[quote]][[/quote]]")
                continue
            }

            // Headings: after block-quote strip so "> # heading" works.
            // No `continue` — inline formatting now applies to heading content.
            if let match = converted.firstMatch(of: /^###\s+(.+)$/) {
                converted = String(match.1)
                blockPrefix += "[[h3]]"
                blockSuffix = "[[/h3]]" + blockSuffix
            } else if let match = converted.firstMatch(of: /^##\s+(.+)$/) {
                converted = String(match.1)
                blockPrefix += "[[h2]]"
                blockSuffix = "[[/h2]]" + blockSuffix
            } else if let match = converted.firstMatch(of: /^#\s+(.+)$/) {
                converted = String(match.1)
                blockPrefix += "[[h1]]"
                blockSuffix = "[[/h1]]" + blockSuffix
            }

            // Task lists: - [x], - [ ], * [x], * [ ], + [x], + [ ]
            converted = converted.replacingOccurrences(
                of: #"^[-*+]\s*\[x\]\s?"#, with: "[x] ", options: .regularExpression
            )
            converted = converted.replacingOccurrences(
                of: #"^[-*+]\s*\[ \]\s?"#, with: "[ ] ", options: .regularExpression
            )

            // Ordered lists: N. text (strip leading whitespace for indented items)
            let strippedForOL = converted.drop(while: { $0 == " " || $0 == "\t" })
            if let match = String(strippedForOL).firstMatch(of: /^(\d+)\.\s+(.*)$/) {
                let num = String(match.1)
                converted = String(match.2)
                blockPrefix += "[[ol|\(num)]]"
            }

            // Unordered list bullets: - item, * item, + item → • prefix
            let strippedForBullet = converted.drop(while: { $0 == " " || $0 == "\t" })
            let bulletStr = String(strippedForBullet)
            if (bulletStr.hasPrefix("- ") && !bulletStr.hasPrefix("- ["))
                || bulletStr.hasPrefix("* ")
                || bulletStr.hasPrefix("+ ")
            {
                converted = "• " + String(bulletStr.dropFirst(2))
            }

            // Images: ![alt](path) — resolve local paths relative to .md dir
            for match in converted.matches(of: /!\[([^\]]*)\]\(([^)]+)\)/).reversed() {
                let path = String(match.2)
                let imageURL: URL
                if let u = URL(string: path), u.scheme != nil {
                    imageURL = u
                } else {
                    imageURL = baseDir.appendingPathComponent(path)
                }
                if let filename = await ImageStorageManager.shared.saveImage(from: imageURL) {
                    converted = converted.replacing(
                        match.0, with: "[[image|||\(filename)]]"
                    )
                }
            }

            // CSV file links: [text](path.csv) — inline as table (Notion exports)
            if let csvMatch = converted.firstMatch(of: /\[([^\]]*)\]\(([^)]+\.csv)\)/) {
                let csvPath = String(csvMatch.2)
                let csvURL: URL
                if let u = URL(string: csvPath), u.scheme != nil {
                    csvURL = u
                } else {
                    let decoded = csvPath.removingPercentEncoding ?? csvPath
                    csvURL = baseDir.appendingPathComponent(decoded)
                }
                if FileManager.default.fileExists(atPath: csvURL.path),
                   let csvText = try? String(contentsOf: csvURL, encoding: .utf8) {
                    let csvRows = csvText.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if !csvRows.isEmpty {
                        let parsedRows = csvRows.map { Self.parseCSVRow($0) }
                        let maxCols = parsedRows.map { $0.count }.max() ?? 1
                        let normalized = parsedRows.map { $0 + Array(repeating: "", count: max(0, maxCols - $0.count)) }
                        let tableData = NoteTableData(columns: maxCols, cells: normalized, columnWidths: Array(repeating: NoteTableData.defaultColumnWidth, count: maxCols))
                        converted = converted.replacing(csvMatch.0, with: "\n" + tableData.serialize())
                    }
                }
            }

            // Links: [text](url)
            converted = replacePattern(
                in: converted, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#
            ) { groups in "[[link|\(groups[2])|\(groups[1])]]" }

            // Bold: **text** or __text__ (before italic to avoid conflicts)
            converted = replacePattern(
                in: converted, pattern: #"\*\*(.+?)\*\*"#
            ) { "[[b]]\($0[1])[[/b]]" }
            converted = replacePattern(
                in: converted, pattern: #"__(.+?)__"#
            ) { "[[b]]\($0[1])[[/b]]" }

            // Italic: *text* or _text_
            converted = replacePattern(
                in: converted, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#
            ) { "[[i]]\($0[1])[[/i]]" }
            converted = replacePattern(
                in: converted, pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#
            ) { "[[i]]\($0[1])[[/i]]" }

            // Strikethrough: ~~text~~
            converted = replacePattern(
                in: converted, pattern: #"~~(.+?)~~"#
            ) { "[[s]]\($0[1])[[/s]]" }

            lines.append(blockPrefix + converted + blockSuffix)
        }

        // Flush any trailing pipe table
        flushPipeTable()

        return (titleFromURL(url), lines.joined(separator: "\n"))
    }

    private func convertHTML(at url: URL) async -> (title: String, content: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let attrString = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) else { return nil }
        return (titleFromURL(url), await attributedStringToMarkup(attrString))
    }

    private func convertRTF(at url: URL) async -> (title: String, content: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let attrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return (titleFromURL(url), await attributedStringToMarkup(attrString))
    }

    private func convertDOCX(at url: URL) async -> (title: String, content: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let attrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        ) else { return nil }
        return (titleFromURL(url), await attributedStringToMarkup(attrString))
    }

    private func convertCSV(at url: URL) -> (title: String, content: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let rows = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !rows.isEmpty else { return (titleFromURL(url), "") }

        let parsedRows = rows.map { Self.parseCSVRow($0) }
        let maxColumns = parsedRows.map { $0.count }.max() ?? 1
        let normalizedRows = parsedRows.map { row in
            row + Array(repeating: "", count: max(0, maxColumns - row.count))
        }

        let tableData = NoteTableData(columns: maxColumns, cells: normalizedRows, columnWidths: Array(repeating: NoteTableData.defaultColumnWidth, count: maxColumns))
        return (titleFromURL(url), tableData.serialize())
    }

    /// Parse a single CSV row, respecting quoted fields
    static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func convertPDF(at url: URL) async -> (title: String, content: String)? {
        guard let document = PDFDocument(url: url) else { return nil }
        var lines: [String] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            if let attrString = page.attributedString {
                let markup = await attributedStringToMarkup(attrString)
                // If attributedStringToMarkup produced zero formatting tags, the PDF
                // has uniform fonts (common in generated/template PDFs). Fall back to
                // heuristic structural detection on the raw text.
                if markup.contains("[[") {
                    lines.append(markup)
                } else {
                    lines.append(applyPDFTextHeuristics(markup))
                }
            } else if let text = page.string {
                lines.append(applyPDFTextHeuristics(text))
            }

            if pageIndex < document.pageCount - 1 {
                lines.append("")
            }
        }

        return (titleFromURL(url), lines.joined(separator: "\n"))
    }

    // MARK: - PDF Heuristic Structure Detection

    /// When PDFKit returns uniform fonts (no bold, no size variation), detect
    /// structure from textual patterns: section headings, numbered lists, etc.
    ///
    /// PDF text extraction often wraps long paragraphs across multiple lines.
    /// This method first rejoins wrapped lines into logical paragraphs, then
    /// applies structural pattern matching.
    private func applyPDFTextHeuristics(_ text: String) -> String {
        let inputLines = text.components(separatedBy: "\n")

        // --- Pass 1: Rejoin wrapped lines into logical paragraphs ---
        // A "continuation" line is one that doesn't start a new structural element
        // and follows a long line (the previous line was near the PDF's line width).
        var paragraphs: [String] = []
        for line in inputLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                paragraphs.append("")
                continue
            }

            let isNewBlock = Self.looksLikeNewBlock(trimmed)
            // Don't join onto a previous line that is a short heading or standalone
            // structural element (address, date, greeting, etc.) — these should stay
            // on their own line. However, numbered list items and long body lines
            // DO accept continuation joins.
            let prevIsShortStructural = paragraphs.last.map {
                Self.isHeadingOrShortStructural($0)
            } ?? false
            if !isNewBlock, !prevIsShortStructural, let last = paragraphs.last,
               !last.isEmpty, last.count > 40
            {
                // Continuation of previous line — join with space
                paragraphs[paragraphs.count - 1] += " " + trimmed
            } else {
                paragraphs.append(trimmed)
            }
        }

        // --- Pass 2: Apply structural markup ---
        var outputLines: [String] = []

        // Roman numeral section heading: "I. Title", "II. Title", etc.
        let romanSectionPattern =
            /^(M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3}))\.\s+(.+)$/
        let letterSectionPattern = /^([A-Z])\.\s+([A-Z].+)$/
        let numberedListPattern = /^(\d+)\.\s+(.+)$/

        for para in paragraphs {
            if para.isEmpty {
                outputLines.append("")
                continue
            }

            // Roman numeral section headings (I., II., III., IV., V., etc.)
            if let match = para.firstMatch(of: romanSectionPattern) {
                let roman = String(match.1)
                let title = String(match.5)
                if !roman.isEmpty && title.count < 120 {
                    outputLines.append("[[h2]]\(para)[[/h2]]")
                    continue
                }
            }

            // Single letter section heading: "A. Title"
            if let match = para.firstMatch(of: letterSectionPattern) {
                let title = String(match.2)
                if title.count < 120 {
                    outputLines.append("[[h3]]\(para)[[/h3]]")
                    continue
                }
            }

            // "Betreff:" / "Subject:" — bold emphasis
            if para.hasPrefix("Betreff:") || para.hasPrefix("Subject:")
                || para.hasPrefix("Betrifft:")
            {
                outputLines.append("[[b]]\(para)[[/b]]")
                continue
            }

            // Numbered list items (1-99)
            if let match = para.firstMatch(of: numberedListPattern) {
                let num = String(match.1)
                let content = String(match.2)
                let numVal = Int(num) ?? 0
                if numVal >= 1 && numVal <= 99 {
                    outputLines.append("[[ol|\(num)]]\(content)")
                    continue
                }
            }

            // En-dash / em-dash bullet items: "– item" or "— item"
            if para.hasPrefix("\u{2013} ") || para.hasPrefix("\u{2014} ") {
                let content = String(para.dropFirst(2))
                outputLines.append("• \(content)")
                continue
            }

            outputLines.append(para)
        }

        return outputLines.joined(separator: "\n")
    }

    /// Determines if a line of text starts a new logical block (heading, list,
    /// address field, greeting) vs. being a continuation of the previous line.
    private static func looksLikeNewBlock(_ line: String) -> Bool {
        // Roman numeral heading: "I. ", "II. ", "III. ", "IV. ", "V. " etc.
        if line.firstMatch(of:
            /^(M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3}))\.\s/) != nil,
           line.first?.isUppercase == true
        {
            return true
        }
        // Numbered list: "1. ", "2. " etc.
        if line.firstMatch(of: /^\d+\.\s/) != nil { return true }
        // En-dash/em-dash bullet
        if line.hasPrefix("\u{2013} ") || line.hasPrefix("\u{2014} ") { return true }
        // Common structural prefixes
        let prefixes = [
            "Betreff:", "Betrifft:", "Subject:", "Aktenzeichen:", "Anlagen:",
            "Bearbeiterin:", "Bearbeiter:", "Ihr Schreiben", "Sehr geehrte",
            "Mit freundlichen", "Hochachtungsvoll", "Dear ", "Sincerely",
        ]
        for p in prefixes where line.hasPrefix(p) { return true }
        // Short line (< 60 chars) is likely a standalone element (address, date, etc.)
        if line.count < 60 { return true }
        // Starts with uppercase after a period-terminated previous line — new sentence block
        // (handled by the caller's length check on prev line)
        return false
    }

    /// Returns true for lines that are headings or short standalone structural elements
    /// (addresses, greetings, signatures) — these should never have continuation lines
    /// appended to them. Numbered list items and body paragraphs return false.
    private static func isHeadingOrShortStructural(_ line: String) -> Bool {
        // Roman numeral heading: never append continuations
        if line.firstMatch(of:
            /^(M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3}))\.\s/) != nil,
           line.first?.isUppercase == true
        {
            return true
        }
        // Short standalone elements (< 60 chars): addresses, dates, greetings
        if line.count < 60 { return true }
        // Structural prefixes that should stay on their own line
        let isolatedPrefixes = [
            "Betreff:", "Betrifft:", "Subject:", "Aktenzeichen:", "Anlagen:",
            "Bearbeiterin:", "Bearbeiter:",
        ]
        for p in isolatedPrefixes where line.hasPrefix(p) { return true }
        return false
    }

    // MARK: - Attributed String -> Markup

    /// List type detected from NSParagraphStyle.textLists
    private enum ImportListType { case none, ordered, unordered }

    /// Convert NSAttributedString to the app's custom markup format.
    /// Inverse of TodoRichTextEditor's deserialization.
    private func attributedStringToMarkup(_ attrString: NSAttributedString) async -> String {
        let fullRange = NSRange(location: 0, length: attrString.length)
        guard fullRange.length > 0 else { return "" }

        // Pre-scan: find the dominant (most common) font size for relative heading detection.
        // Weighted by character count so body text naturally dominates.
        var fontSizeWeights: [CGFloat: Int] = [:]
        attrString.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if let font = value as? NSFont {
                let rounded = (font.pointSize * 2).rounded() / 2
                fontSizeWeights[rounded, default: 0] += range.length
            }
        }
        let baseFontSize = fontSizeWeights.max(by: { $0.value < $1.value })?.key ?? 12.0

        let text = attrString.string
        let paragraphs = text.components(separatedBy: "\n")
        var result = ""
        var location = 0

        for (pIndex, paragraph) in paragraphs.enumerated() {
            let paraLength = (paragraph as NSString).length
            let paraRange = NSRange(location: location, length: paraLength)

            guard paraRange.location + paraRange.length <= attrString.length else { break }

            // Paragraph-level attributes
            var alignment: NSTextAlignment = .left
            var listType: ImportListType = .none
            var paragraphSpacingBefore: CGFloat = 0

            if paraLength > 0,
                let paraStyle = attrString.attribute(
                    .paragraphStyle, at: paraRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle
            {
                alignment = paraStyle.alignment
                paragraphSpacingBefore = paraStyle.paragraphSpacingBefore

                // Detect list items via NSTextList (used by Apple's HTML/RTF/DOCX converters)
                if let textList = paraStyle.textLists.last {
                    let format = textList.markerFormat
                    let orderedFormats: [NSTextList.MarkerFormat] = [
                        .decimal, .lowercaseAlpha, .uppercaseAlpha,
                        .lowercaseLatin, .uppercaseLatin,
                        .lowercaseRoman, .uppercaseRoman, .octal,
                    ]
                    listType = orderedFormats.contains(format) ? .ordered : .unordered
                }
            }

            let headingLevel = detectHeadingLevel(
                in: attrString, range: paraRange, baseFontSize: baseFontSize
            )

            // Insert blank line for significant paragraph spacing (preserves visual separation)
            if pIndex > 0 && paragraphSpacingBefore > baseFontSize * 0.75
                && headingLevel == 0 && listType == .none
            {
                result += "\n"
            }

            // Collect attribute runs synchronously
            var runs: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
            if paraLength > 0 {
                attrString.enumerateAttributes(in: paraRange) { attrs, range, _ in
                    runs.append((range, attrs))
                }
            }

            // Process runs (async for image attachment handling)
            var paraContent = ""
            for (range, attrs) in runs {
                let substring = (attrString.string as NSString).substring(with: range)

                // Image attachments
                if let attachment = attrs[.attachment] as? NSTextAttachment {
                    if let filename = await saveAttachmentImage(from: attachment) {
                        paraContent += "[[image|||\(filename)]]"
                    }
                    continue
                }

                let font = attrs[.font] as? NSFont
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                let isBold = traits.contains(.bold) && headingLevel == 0
                let isItalic = traits.contains(.italic)
                let hasUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                let hasStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0

                var colorHex: String?
                if let color = attrs[.foregroundColor] as? NSColor {
                    let resolved = color.usingColorSpace(.sRGB)
                        ?? color.usingColorSpace(.deviceRGB)
                    if let resolved, !isDefaultTextColor(resolved) {
                        colorHex = hexFromNSColor(resolved)
                    }
                }

                // Nesting: bold/italic > underline > strikethrough > color
                var wrapped = substring
                if let hex = colorHex { wrapped = "[[color|\(hex)]]\(wrapped)[[/color]]" }
                if hasStrikethrough { wrapped = "[[s]]\(wrapped)[[/s]]" }
                if hasUnderline { wrapped = "[[u]]\(wrapped)[[/u]]" }
                if isItalic { wrapped = "[[i]]\(wrapped)[[/i]]" }
                if isBold { wrapped = "[[b]]\(wrapped)[[/b]]" }

                paraContent += wrapped
            }

            // Strip list marker prefix inserted by Apple's converters (e.g. "\t•\t", "\t1.\t")
            var orderedListNumber = 0
            if listType != .none {
                let (stripped, num) = Self.stripListMarkerFromContent(
                    paraContent, listType: listType
                )
                paraContent = stripped
                orderedListNumber = num
            }

            // Detect and normalize bullet characters in text (common in PDFs)
            if listType == .none {
                paraContent = Self.normalizeBulletPrefix(paraContent)
            }

            // List markup wrapper
            if listType == .ordered {
                let num = orderedListNumber > 0 ? orderedListNumber : 1
                paraContent = "[[ol|\(num)]]\(paraContent)"
            } else if listType == .unordered {
                paraContent = "• \(paraContent)"
            }

            // Heading wrapper
            if headingLevel > 0 {
                paraContent = "[[h\(headingLevel)]]\(paraContent)[[/h\(headingLevel)]]"
            }

            // Alignment wrapper (outermost per convention)
            switch alignment {
            case .center:    paraContent = "[[align:center]]\(paraContent)[[/align]]"
            case .right:     paraContent = "[[align:right]]\(paraContent)[[/align]]"
            case .justified: paraContent = "[[align:justify]]\(paraContent)[[/align]]"
            default: break
            }

            result += paraContent
            if pIndex < paragraphs.count - 1 { result += "\n" }

            location += paraLength + 1
        }

        return result
    }

    // MARK: - Helpers

    private func titleFromURL(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func detectHeadingLevel(
        in attrString: NSAttributedString,
        range: NSRange,
        baseFontSize: CGFloat
    ) -> Int {
        guard range.length > 0 else { return 0 }
        guard let font = attrString.attribute(
            .font, at: range.location, effectiveRange: nil
        ) as? NSFont else { return 0 }

        let size = font.pointSize
        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)

        // Relative detection: compare against the document's dominant body font size.
        // Falls back to 12pt when base is unknown, preserving the old absolute thresholds.
        let effectiveBase = baseFontSize > 0 ? baseFontSize : 12.0
        let ratio = size / effectiveBase

        if ratio >= 2.0 || (isBold && ratio >= 1.67) { return 1 }
        if ratio >= 1.5 || (isBold && ratio >= 1.33) { return 2 }
        if ratio >= 1.17 && isBold { return 3 }

        return 0
    }

    private func isDefaultTextColor(_ color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return true }
        return c.redComponent < 0.15 && c.greenComponent < 0.15 && c.blueComponent < 0.15
    }

    private func hexFromNSColor(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "000000" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// Save an NSTextAttachment image to storage via temp file
    private func saveAttachmentImage(from attachment: NSTextAttachment) async -> String? {
        var imageData: Data?

        if let image = attachment.image,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        {
            imageData = rep.representation(using: .png, properties: [:])
        } else if let data = attachment.contents ?? attachment.fileWrapper?.regularFileContents {
            imageData = data
        }

        guard let data = imageData else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return await ImageStorageManager.shared.saveImage(from: tempURL)
        } catch {
            return nil
        }
    }

    /// Strip list marker prefix (e.g. "\t•\t", "\t1.\t") inserted by Apple's
    /// NSAttributedString HTML/RTF/DOCX converters.
    private static func stripListMarkerFromContent(
        _ content: String,
        listType: ImportListType
    ) -> (stripped: String, number: Int) {
        var number = 0
        var s = content

        // Strip leading tabs/spaces (Apple's converters indent list markers)
        let leadingWS = s.prefix(while: { $0 == "\t" || $0 == " " })
        s = String(s.dropFirst(leadingWS.count))

        if listType == .ordered {
            // Extract "N." or "N)" prefix
            if let regex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s*"#),
               let match = regex.firstMatch(
                   in: s, range: NSRange(location: 0, length: (s as NSString).length)
               )
            {
                let numRange = match.range(at: 1)
                if numRange.location != NSNotFound {
                    number = Int((s as NSString).substring(with: numRange)) ?? 1
                }
                if let range = Range(match.range, in: s) {
                    s = String(s[range.upperBound...])
                }
            }
        }

        // Strip known bullet characters
        let bulletChars: Set<Character> = [
            "\u{2022}", "\u{2023}", "\u{25AA}", "\u{25B8}", "\u{25BA}",
            "\u{25E6}", "\u{25CB}", "\u{25A0}", "\u{25A1}", "\u{25CF}",
            "\u{25C6}", "\u{25C7}", "\u{2013}", "\u{2014}", "-",
        ]
        if let first = s.first, bulletChars.contains(first) {
            s = String(s.dropFirst())
        }

        // Strip whitespace/tab after marker
        let trailingWS = s.prefix(while: { $0 == "\t" || $0 == " " })
        s = String(s.dropFirst(trailingWS.count))

        return (s, number)
    }

    /// Normalize common bullet prefix characters found in PDFs to the standard "• ".
    private static func normalizeBulletPrefix(_ text: String) -> String {
        let bulletChars: Set<Character> = [
            "\u{2023}", "\u{25AA}", "\u{25B8}", "\u{25BA}",
            "\u{25E6}", "\u{25CB}", "\u{25A0}", "\u{25A1}", "\u{25CF}",
            "\u{25C6}", "\u{25C7}",
        ]
        guard let first = text.first, bulletChars.contains(first) else { return text }

        var rest = text.dropFirst()
        while rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return "• " + rest
    }

    /// Regex replacement helper — processes matches in reverse for safe mutation
    private func replacePattern(
        in string: String,
        pattern: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: string, range: range)

        var result = string
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(
                    r.location != NSNotFound ? nsString.substring(with: r) : ""
                )
            }
            let replacement = transform(groups)
            if let swiftRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: swiftRange, with: replacement)
            }
        }
        return result
    }
}
