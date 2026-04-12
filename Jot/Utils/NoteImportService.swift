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

    /// Resolves a path relative to `baseDir` and returns nil if the result escapes the
    /// import folder (e.g. via `../`) after standardization and symlink resolution.
    private func canonicalFileURLIfUnderBase(relativePath: String, baseDir: URL) -> URL? {
        let decoded = relativePath.removingPercentEncoding ?? relativePath
        if decoded.hasPrefix("/") { return nil }
        let combined = baseDir.appendingPathComponent(decoded)
        let abs = combined.standardizedFileURL.resolvingSymlinksInPath()
        let base = baseDir.standardizedFileURL.resolvingSymlinksInPath()
        let basePath = base.path
        let absPath = abs.path
        guard absPath == basePath || absPath.hasPrefix(basePath + "/") else { return nil }
        return abs
    }

    // MARK: - Converters

    private func convertTXT(at url: URL) -> (title: String, content: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (titleFromURL(url), text)
    }

    private func convertMarkdown(at url: URL) async -> (title: String, content: String)? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let baseDir = url.deletingLastPathComponent()

        // Pre-pass: convert setext-style headings to ATX-style
        // (Title\n=== -> # Title, Subtitle\n--- -> ## Subtitle)
        let rawLines = raw.components(separatedBy: .newlines)
        var preprocessed: [String] = []
        var idx = 0
        while idx < rawLines.count {
            let current = rawLines[idx]
            let currentTrimmed = current.trimmingCharacters(in: .whitespaces)
            if idx + 1 < rawLines.count && !currentTrimmed.isEmpty {
                let nextTrimmed = rawLines[idx + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.count >= 2 && nextTrimmed.allSatisfy({ $0 == "=" }) {
                    preprocessed.append("# \(currentTrimmed)")
                    idx += 2
                    continue
                } else if nextTrimmed.count >= 2 && nextTrimmed.allSatisfy({ $0 == "-" }) {
                    preprocessed.append("## \(currentTrimmed)")
                    idx += 2
                    continue
                }
            }
            preprocessed.append(current)
            idx += 1
        }

        var lines: [String] = []
        var codeBlockLanguage: String? = nil   // nil = not inside a code block
        var codeBlockLines: [String] = []
        var indentedCodeLines: [String]? = nil  // nil = not inside an indented block
        var pendingTableRows: [[String]] = []
        var quoteLines: [String] = []
        var isCallout = false
        var calloutType = "note"

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

        /// Flush accumulated blockquote lines
        func flushQuoteBlock() {
            guard !quoteLines.isEmpty else { return }
            if isCallout {
                let content = quoteLines.joined(separator: "\n")
                let escaped = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\n", with: "\\n")
                lines.append("[[callout|\(calloutType)]]\(escaped)[[/callout]]")
            } else {
                for ql in quoteLines {
                    lines.append("[[quote]]\(ql)[[/quote]]")
                }
            }
            quoteLines.removeAll()
            isCallout = false
            calloutType = "note"
        }

        /// Flush accumulated indented code block lines
        func flushIndentedCode() {
            guard let codeLines = indentedCodeLines, !codeLines.isEmpty else {
                indentedCodeLines = nil
                return
            }
            let code = codeLines.joined(separator: "\n")
            let data = CodeBlockData(language: "plaintext", code: code)
            lines.append(data.serialize())
            indentedCodeLines = nil
        }

        for line in preprocessed {
            // Code fences — accumulate into CodeBlockData
            if line.hasPrefix("```") {
                flushPipeTable()
                if codeBlockLanguage != nil {
                    // Closing fence — emit code block
                    let lang = codeBlockLanguage ?? "plaintext"
                    let code = codeBlockLines.joined(separator: "\n")
                    let data = CodeBlockData(language: lang, code: code)
                    lines.append(data.serialize())
                    codeBlockLanguage = nil
                    codeBlockLines.removeAll()
                } else {
                    // Opening fence — extract language hint
                    let hint = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeBlockLanguage = Self.normalizeCodeLanguage(hint)
                }
                continue
            }
            if codeBlockLanguage != nil {
                codeBlockLines.append(line)
                continue
            }

            // Indented code blocks: 4+ spaces or 1 tab prefix
            let indentedContent: String?
            if line.hasPrefix("    ") {
                indentedContent = String(line.dropFirst(4))
            } else if line.hasPrefix("\t") {
                indentedContent = String(line.dropFirst(1))
            } else {
                indentedContent = nil
            }
            if let codeContent = indentedContent {
                flushPipeTable()
                flushQuoteBlock()
                if indentedCodeLines == nil { indentedCodeLines = [] }
                indentedCodeLines!.append(codeContent)
                continue
            } else {
                flushIndentedCode()
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
            // Soft line break: strip 2+ trailing spaces (Markdown line-break signal)
            converted = converted.replacingOccurrences(of: #"\s{2,}$"#, with: "", options: .regularExpression)
            var blockPrefix = ""
            var blockSuffix = ""

            // Horizontal rules: ---, ***, ___  → divider tag
            let hrTrimmed = converted.trimmingCharacters(in: .whitespaces)
            if hrTrimmed.count >= 3,
               hrTrimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }),
               Set(hrTrimmed).count == 1
            {
                lines.append("[[divider]]")
                continue
            }

            // Block quotes: accumulate multi-line > blocks (nested >> flattened to single level)
            let isQuote = converted.hasPrefix(">")
            if isQuote {
                let quoteLine = converted.replacingOccurrences(of: #"^(>\s?)+"#, with: "", options: .regularExpression)
                // Detect callout syntax on first line: > [!type]
                if quoteLines.isEmpty {
                    if let calloutMatch = quoteLine.firstMatch(of: /^\[!(\w+)\]\s*(.*)$/) {
                        let rawType = String(calloutMatch.1).lowercased()
                        if let normalized = Self.normalizeCalloutType(rawType) {
                            isCallout = true
                            calloutType = normalized
                            let remainder = String(calloutMatch.2)
                            if !remainder.isEmpty {
                                quoteLines.append(remainder)
                            }
                        } else {
                            quoteLines.append(quoteLine)
                        }
                    } else {
                        quoteLines.append(quoteLine)
                    }
                } else {
                    quoteLines.append(quoteLine)
                }
                continue
            } else {
                // Non-quote line — flush accumulated quote block
                flushQuoteBlock()
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
            let leadingOL = converted.prefix(while: { $0 == " " || $0 == "\t" })
            let olIndentDepth = leadingOL.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            let strippedForOL = converted.drop(while: { $0 == " " || $0 == "\t" })
            if let match = String(strippedForOL).firstMatch(of: /^(\d+)\.\s+(.*)$/) {
                let num = String(match.1)
                converted = String(match.2)
                let indent = String(repeating: "  ", count: olIndentDepth)
                blockPrefix += "\(indent)[[ol|\(num)]]"
            }

            // Unordered list bullets: - item, * item, + item → • prefix
            let leadingBullet = converted.prefix(while: { $0 == " " || $0 == "\t" })
            let bulletIndentDepth = leadingBullet.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            let strippedForBullet = converted.drop(while: { $0 == " " || $0 == "\t" })
            let bulletStr = String(strippedForBullet)
            if (bulletStr.hasPrefix("- ") && !bulletStr.hasPrefix("- ["))
                || bulletStr.hasPrefix("* ")
                || bulletStr.hasPrefix("+ ")
            {
                let indent = String(repeating: "  ", count: bulletIndentDepth)
                converted = "\(indent)\u{2022} " + String(bulletStr.dropFirst(2))
            }

            // Images: ![alt](path) — resolve local paths relative to .md dir
            for match in converted.matches(of: /!\[([^\]]*)\]\(([^)]+)\)/).reversed() {
                let path = String(match.2)
                let imageURL: URL?
                if let u = URL(string: path), u.scheme != nil {
                    imageURL = u
                } else {
                    imageURL = canonicalFileURLIfUnderBase(relativePath: path, baseDir: baseDir)
                }
                guard let resolvedImageURL = imageURL else { continue }
                if let filename = await ImageStorageManager.shared.saveImage(from: resolvedImageURL) {
                    converted = converted.replacing(
                        match.0, with: "[[image|||\(filename)]]"
                    )
                }
            }

            // CSV file links: [text](path.csv) — inline as table (Notion exports)
            if let csvMatch = converted.firstMatch(of: /\[([^\]]*)\]\(([^)]+\.csv)\)/) {
                let csvPath = String(csvMatch.2)
                let csvURL: URL?
                if let u = URL(string: csvPath), u.scheme != nil {
                    csvURL = u
                } else {
                    let decoded = csvPath.removingPercentEncoding ?? csvPath
                    csvURL = canonicalFileURLIfUnderBase(relativePath: decoded, baseDir: baseDir)
                }
                if let resolvedCsvURL = csvURL,
                   FileManager.default.fileExists(atPath: resolvedCsvURL.path),
                   let csvText = try? String(contentsOf: resolvedCsvURL, encoding: .utf8) {
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

            // Bare URLs: detect URLs not already inside [[link|...]] tags
            if !converted.contains("[[link|") {
                converted = replacePattern(
                    in: converted,
                    pattern: #"(https?://[^\s\)\]\>]+)"#
                ) { "[[link|\($0[1])|\($0[1])]]" }
            }

            // Bold-italic: ***text*** or ___text___ (before bold/italic to consume triple delimiters first)
            converted = replacePattern(
                in: converted, pattern: #"\*{3}(.+?)\*{3}"#
            ) { "[[b]][[i]]\($0[1])[[/i]][[/b]]" }
            converted = replacePattern(
                in: converted, pattern: #"_{3}(.+?)_{3}"#
            ) { "[[b]][[i]]\($0[1])[[/i]][[/b]]" }

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

            // Inline code: `code` → bold (no inline-code markup exists in the editor)
            converted = replacePattern(
                in: converted, pattern: #"`([^`\n]+)`"#
            ) { "[[b]]\($0[1])[[/b]]" }

            lines.append(blockPrefix + converted + blockSuffix)
        }

        flushIndentedCode()
        flushQuoteBlock()

        // Flush any trailing pipe table
        flushPipeTable()

        return (titleFromURL(url), collapseExcessiveBlankLines(lines.joined(separator: "\n")))
    }

    private func convertHTML(at url: URL) async -> (title: String, content: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var htmlString = String(data: data, encoding: .utf8) else { return nil }

        // Pre-extract semantic blocks that Apple's converter loses
        let (processedHTML, placeholders) = Self.extractSemanticHTMLBlocks(htmlString)
        htmlString = processedHTML

        guard let processedData = htmlString.data(using: .utf8),
              let attrString = try? NSAttributedString(
                data: processedData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else { return nil }

        var markup = await attributedStringToMarkup(attrString)

        // Restore semantic placeholders
        for (placeholder, replacement) in placeholders {
            markup = markup.replacingOccurrences(of: placeholder, with: replacement)
        }

        return (titleFromURL(url), markup)
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

        return (titleFromURL(url), collapseExcessiveBlankLines(lines.joined(separator: "\n")))
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
               !last.isEmpty, last.count > 65
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

        return collapseExcessiveBlankLines(outputLines.joined(separator: "\n"))
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
            // Threshold raised to 1.5x — Apple's converters routinely set paragraphSpacingBefore
            // equal to font size (ratio 1.0), which triggered phantom blank lines at 0.75x.
            if pIndex > 0
                && paragraphSpacingBefore > baseFontSize * 1.5
                && headingLevel == 0 && listType == .none
                && !result.hasSuffix("\n\n")
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

                // Link attribute — emit [[link|...]] and skip formatting
                if let linkURL = attrs[.link] as? URL ?? (attrs[.link] as? String).flatMap(URL.init(string:)) {
                    let urlString = linkURL.absoluteString
                    if substring == urlString || substring.isEmpty {
                        paraContent += "[[link|\(urlString)]]"
                    } else {
                        paraContent += "[[link|\(urlString)|\(substring)]]"
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

        return collapseExcessiveBlankLines(result)
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
        // Check for known system text colors by catalog name
        if let catalogName = color.colorNameComponent as String? {
            let systemNames: Set<String> = ["labelColor", "textColor", "controlTextColor",
                                            "secondaryLabelColor", "tertiaryLabelColor",
                                            "quaternaryLabelColor"]
            if systemNames.contains(catalogName) { return true }
        }

        guard let c = color.usingColorSpace(.sRGB) else { return true }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent

        // Near-black (light mode default) or near-white (dark mode labelColor resolved)
        let isNearBlack = r < 0.15 && g < 0.15 && b < 0.15
        let isNearWhite = r > 0.85 && g > 0.85 && b > 0.85
        return isNearBlack || isNearWhite
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

    /// Collapse 3+ consecutive newlines into exactly 2 (one visual blank line).
    private func collapseExcessiveBlankLines(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\n{3,}") else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "\n\n"
        )
    }

    /// Normalize a code-fence language hint to a supported CodeBlockData language.
    private static func normalizeCodeLanguage(_ raw: String) -> String {
        let aliases: [String: String] = [
            "js": "javascript", "ts": "typescript", "py": "python",
            "sh": "bash", "shell": "bash", "c++": "cpp", "c#": "csharp",
            "rb": "ruby", "yml": "yaml", "objc": "swift",
            "objective-c": "swift",
        ]
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty { return "plaintext" }
        let resolved = aliases[lower] ?? lower
        return CodeBlockData.supportedLanguages.contains(resolved) ? resolved : "plaintext"
    }

    /// Map callout/admonition type aliases to CalloutData.CalloutType raw values.
    private static func normalizeCalloutType(_ raw: String) -> String? {
        let mapping: [String: String] = [
            "info": "info", "warning": "warning", "warn": "warning",
            "caution": "warning", "tip": "tip", "hint": "tip",
            "note": "note", "important": "important", "danger": "warning",
            "error": "warning", "success": "tip", "abstract": "note",
            "summary": "note", "todo": "note", "example": "info",
            "question": "info", "faq": "info", "bug": "warning",
            "quote": "note", "cite": "note",
        ]
        return mapping[raw.lowercased()]
    }

    /// Pre-extract semantic HTML blocks (code, hr, callouts) that Apple's
    /// NSAttributedString converter discards, replacing them with placeholders.
    private static func extractSemanticHTMLBlocks(_ html: String) -> (processedHTML: String, placeholders: [String: String]) {
        var result = html
        var placeholders: [String: String] = [:]
        var counter = 0

        func nextPlaceholder() -> String {
            counter += 1
            return "JOTPLACEHOLDER_\(counter)"
        }

        // <pre><code class="language-X">...</code></pre> → code block
        if let regex = try? NSRegularExpression(
            pattern: #"<pre[^>]*>\s*<code(?:\s+class="(?:language-)?([^"]*)")?[^>]*>([\s\S]*?)</code>\s*</pre>"#,
            options: .caseInsensitive
        ) {
            let nsString = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed() {
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                let lang = langRange.location != NSNotFound ? nsString.substring(with: langRange) : ""
                var code = codeRange.location != NSNotFound ? nsString.substring(with: codeRange) : ""
                code = Self.unescapeHTMLEntities(code)
                let normalized = normalizeCodeLanguage(lang)
                let data = CodeBlockData(language: normalized, code: code)
                let placeholder = nextPlaceholder()
                placeholders[placeholder] = data.serialize()
                if let range = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: range, with: placeholder)
                }
            }
        }

        // <hr> → divider
        if let regex = try? NSRegularExpression(pattern: #"<hr\s*/?>"#, options: .caseInsensitive) {
            let nsString = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed() {
                let placeholder = nextPlaceholder()
                placeholders[placeholder] = "[[divider]]"
                if let range = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: range, with: placeholder)
                }
            }
        }

        return (result, placeholders)
    }

    /// Unescape common HTML entities in extracted code content.
    private static func unescapeHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
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
