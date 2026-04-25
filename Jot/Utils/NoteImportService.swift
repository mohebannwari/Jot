//
//  NoteImportService.swift
//  Jot
//
//  Handles importing notes from various file formats (PDF, Markdown, HTML,
//  TXT, RTF, DOCX) with conversion to the app's custom markup format.
//

import AppKit
import Foundation
import Markdown
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

    private struct ImportResult {
        let title: String
        let content: String
        let tags: [String]
    }

    private struct MarkdownFrontmatter {
        let body: String
        let title: String?
        let tags: [String]
    }

    // MARK: - Public API

    /// Import a single file, returning the created Note
    func importFile(
        at url: URL,
        into manager: SimpleSwiftDataManager,
        folderID: UUID? = nil
    ) async -> Note? {
        guard let format = NoteImportFormat.from(url: url) else { return nil }

        let result: ImportResult?

        switch format {
        case .txt:      result = convertTXT(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        case .markdown: result = await convertMarkdown(at: url)
        case .html:     result = await convertHTML(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        case .rtf:      result = await convertRTF(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        case .docx:     result = await convertDOCX(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        case .pdf:      result = await convertPDF(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        case .csv:      result = convertCSV(at: url).map { ImportResult(title: $0.title, content: $0.content, tags: []) }
        }

        guard let result else { return nil }
        return manager.addNote(title: result.title, content: result.content, tags: result.tags, folderID: folderID)
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

    private func convertMarkdown(at url: URL) async -> ImportResult? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return await convertMarkdownDocumentResult(
            raw: raw,
            baseDirectory: url.deletingLastPathComponent(),
            fileURLForFallbackTitle: url
        )
    }

    /// Converts a Markdown string to Jot markup (shared by file import and unit tests).
    /// Kept as a tuple shim for existing tests; file import uses `convertMarkdownDocumentResult`
    /// so YAML tags can be persisted on the created note.
    internal func convertMarkdownDocument(
        raw: String,
        baseDirectory: URL,
        fileURLForFallbackTitle: URL
    ) async -> (title: String, content: String) {
        let result = await convertMarkdownDocumentResult(
            raw: raw,
            baseDirectory: baseDirectory,
            fileURLForFallbackTitle: fileURLForFallbackTitle
        )
        return (result.title, result.content)
    }

    private func convertMarkdownDocumentResult(
        raw: String,
        baseDirectory: URL,
        fileURLForFallbackTitle: URL
    ) async -> ImportResult {
        let frontmatter = Self.parseLeadingYAMLFrontmatter(raw)
        let document = Document(parsing: frontmatter.body)
        var blocks = Array(document.children)

        var resolvedTitle = frontmatter.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedTitle?.isEmpty == true { resolvedTitle = nil }

        if let firstContentIndex = blocks.firstIndex(where: { !Self.markdownPlainText($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0 is ThematicBreak || $0 is CodeBlock || $0 is Table }),
           let heading = blocks[firstContentIndex] as? Heading,
           heading.level == 1 {
            let headingTitle = Self.markdownPlainText(heading).trimmingCharacters(in: .whitespacesAndNewlines)
            if !headingTitle.isEmpty {
                resolvedTitle = headingTitle
                blocks.remove(at: firstContentIndex)
            }
        }

        let lines = await renderMarkdownBlocks(blocks, baseDirectory: baseDirectory, indent: 0)
        let normalized = normalizeImportedMarkdownLines(lines)
        let title = resolvedTitle ?? titleFromURL(fileURLForFallbackTitle)
        return ImportResult(title: title, content: normalized.joined(separator: "\n"), tags: frontmatter.tags)
    }

    private static func parseLeadingYAMLFrontmatter(_ raw: String) -> MarkdownFrontmatter {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return MarkdownFrontmatter(body: raw, title: nil, tags: [])
        }

        var closeIndex: Int?
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            closeIndex = index
            break
        }
        guard let closeIndex else {
            return MarkdownFrontmatter(body: raw, title: nil, tags: [])
        }

        let frontmatterLines = Array(lines[1..<closeIndex])
        // Only strip when the interior is actually YAML. A bare `---...---` block whose
        // contents are markdown (headings, bold, free prose) is a CommonMark thematic
        // break around body content, not metadata — preserving it matches what every
        // spec-compliant viewer renders.
        guard looksLikeYAMLFrontmatter(frontmatterLines) else {
            return MarkdownFrontmatter(body: raw, title: nil, tags: [])
        }

        let body = lines.dropFirst(closeIndex + 1).joined(separator: "\n")
        return MarkdownFrontmatter(
            body: body,
            title: parseYAMLTitle(frontmatterLines),
            tags: parseYAMLTags(frontmatterLines)
        )
    }

    /// Conservative YAML-shape check. Returns `true` only when every non-empty line is a
    /// recognized YAML construct (key/value, indented list item, comment, block-scalar
    /// continuation) AND at least one line is a key. Fail-closed: any line that doesn't
    /// fit means "not frontmatter, leave the block as body content."
    private static func looksLikeYAMLFrontmatter(_ lines: [String]) -> Bool {
        var sawKey = false
        var insideBlockScalar = false

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            // Block-scalar continuation (line is indented after a `key: |` / `key: >` / `key:` opener).
            if insideBlockScalar {
                if raw.first?.isWhitespace == true {
                    continue
                }
                insideBlockScalar = false
            }
            // Markdown heading (`##` or deeper) — never YAML.
            if trimmed.hasPrefix("##") {
                return false
            }
            // YAML comment: `# foo` or a bare `#`.
            if trimmed.hasPrefix("# ") || trimmed == "#" {
                insideBlockScalar = false
                continue
            }
            // Indented list item: `  - foo` (`tags:` continuation, etc.).
            if raw.first?.isWhitespace == true, trimmed.hasPrefix("- ") {
                insideBlockScalar = false
                continue
            }
            // Top-level list item (rare but valid YAML).
            if trimmed.hasPrefix("- ") {
                insideBlockScalar = false
                continue
            }
            // `key: value` — key must be a valid YAML identifier.
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex])
                if isValidYAMLKey(key) {
                    sawKey = true
                    let value = String(trimmed[trimmed.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                    insideBlockScalar = value.isEmpty || value == "|" || value == ">"
                    continue
                }
            }
            // Markdown bold, free prose, malformed key — not YAML.
            return false
        }

        return sawKey
    }

    private static func isValidYAMLKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.unicodeScalars.first else { return false }
        let firstAllowed = (first >= "A" && first <= "Z")
            || (first >= "a" && first <= "z")
            || first == "_"
        guard firstAllowed else { return false }
        for scalar in trimmed.unicodeScalars.dropFirst() {
            let allowed = (scalar >= "A" && scalar <= "Z")
                || (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9")
                || scalar == "_"
                || scalar == "-"
            if !allowed { return false }
        }
        return true
    }

    private static func parseYAMLTitle(_ lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("title:") else { continue }
            return cleanYAMLScalar(String(trimmed.dropFirst("title:".count)))
        }
        return nil
    }

    private static func parseYAMLTags(_ lines: [String]) -> [String] {
        var tags: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("tags:") else {
                index += 1
                continue
            }

            let value = String(trimmed.dropFirst("tags:".count)).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                tags += inner.split(separator: ",").map { cleanYAMLTag(String($0)) }
            } else if !value.isEmpty {
                tags += value.split(separator: ",").map { cleanYAMLTag(String($0)) }
            } else {
                var childIndex = index + 1
                while childIndex < lines.count {
                    let child = lines[childIndex].trimmingCharacters(in: .whitespaces)
                    guard child.hasPrefix("- ") else { break }
                    tags.append(cleanYAMLTag(String(child.dropFirst(2))))
                    childIndex += 1
                }
                index = childIndex - 1
            }
            index += 1
        }

        var seen: Set<String> = []
        return tags.compactMap { tag in
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { return nil }
            seen.insert(cleaned)
            return cleaned
        }
    }

    private static func cleanYAMLScalar(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    private static func cleanYAMLTag(_ raw: String) -> String {
        var value = cleanYAMLScalar(raw)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderMarkdownBlocks(
        _ blocks: [Markup],
        baseDirectory: URL,
        indent: Int
    ) async -> [String] {
        var lines: [String] = []
        for block in blocks {
            lines += await renderMarkdownBlock(block, baseDirectory: baseDirectory, indent: indent)
        }
        return lines
    }

    private func renderMarkdownBlock(
        _ block: Markup,
        baseDirectory: URL,
        indent: Int
    ) async -> [String] {
        let continuationPrefix = String(repeating: "  ", count: indent)

        switch block {
        case let document as Document:
            return await renderMarkdownBlocks(Array(document.children), baseDirectory: baseDirectory, indent: indent)
        case let paragraph as Paragraph:
            let content = await renderInlineChildren(paragraph, baseDirectory: baseDirectory)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return content.components(separatedBy: "\n").compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                return line.isEmpty ? nil : continuationPrefix + normalizeImportedLinePrefix(line)
            }
        case let heading as Heading:
            let content = await renderInlineChildren(heading, baseDirectory: baseDirectory)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let level = min(max(heading.level, 1), 3)
            return ["[[h\(level)]]\(content)[[/h\(level)]]"]
        case is ThematicBreak:
            return ["[[divider]]"]
        case let codeBlock as CodeBlock:
            let language = Self.normalizeCodeLanguage(codeBlock.language ?? "")
            return [CodeBlockData(language: language, code: Self.normalizedMarkdownCodeBlockBody(codeBlock.code)).serialize()]
        case let htmlBlock as HTMLBlock:
            let rawHTML = htmlBlock.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            return rawHTML.isEmpty ? [] : [JotMarkupLiteral.escapeIfNeeded(rawHTML)]
        case let quote as BlockQuote:
            return await renderMarkdownBlockQuote(quote, baseDirectory: baseDirectory)
        case let list as OrderedList:
            return await renderOrderedList(list, baseDirectory: baseDirectory, indent: indent)
        case let list as UnorderedList:
            return await renderUnorderedList(list, baseDirectory: baseDirectory, indent: indent)
        case let table as Table:
            return [renderMarkdownTable(table)]
        default:
            let text = Self.markdownPlainText(block).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [continuationPrefix + JotMarkupLiteral.escapeIfNeeded(text)]
        }
    }

    private func renderMarkdownBlockQuote(_ quote: BlockQuote, baseDirectory: URL) async -> [String] {
        let quoteLines = await renderMarkdownBlocks(Array(quote.children), baseDirectory: baseDirectory, indent: 0)
        guard let first = quoteLines.first else { return [] }
        let trimmedFirst = first.trimmingCharacters(in: .whitespaces)

        if let callout = Self.parseObsidianCalloutMarker(trimmedFirst) {
            let normalized = Self.normalizeCalloutType(callout.type) ?? "note"
            let calloutType = CalloutData.CalloutType(rawValue: normalized) ?? .note
            var bodyLines: [String] = []
            if !callout.title.isEmpty {
                bodyLines.append(callout.title)
            }
            bodyLines += quoteLines.dropFirst()
            return [CalloutData(type: calloutType, content: bodyLines.joined(separator: "\n")).serialize()]
        }

        return quoteLines.map { "[[quote]]\($0)[[/quote]]" }
    }

    private static func parseObsidianCalloutMarker(_ line: String) -> (type: String, title: String)? {
        guard line.hasPrefix("[!") else { return nil }
        guard let close = line.firstIndex(of: "]") else { return nil }
        let marker = line[line.index(line.startIndex, offsetBy: 2)..<close]
        guard !marker.isEmpty else { return nil }
        var type = String(marker).lowercased()
        if type.hasSuffix("+") || type.hasSuffix("-") {
            type.removeLast()
        }
        var remainder = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        if remainder.hasPrefix("+") || remainder.hasPrefix("-") {
            remainder.removeFirst()
            remainder = remainder.trimmingCharacters(in: .whitespaces)
        }
        let title = remainder
        return (type, title)
    }

    private func renderOrderedList(_ list: OrderedList, baseDirectory: URL, indent: Int) async -> [String] {
        var lines: [String] = []
        let start = Int(list.startIndex)
        for (offset, child) in Array(list.children).enumerated() {
            guard let item = child as? Markdown.ListItem else { continue }
            lines += await renderListItem(
                item,
                marker: "[[ol|\(start + offset)]]",
                baseDirectory: baseDirectory,
                indent: indent
            )
        }
        return lines
    }

    private func renderUnorderedList(_ list: UnorderedList, baseDirectory: URL, indent: Int) async -> [String] {
        var lines: [String] = []
        for child in list.children {
            guard let item = child as? Markdown.ListItem else { continue }
            let marker: String
            switch item.checkbox {
            case .some(.checked):
                marker = "[x] "
            case .some(.unchecked):
                marker = "[ ] "
            case nil:
                marker = "• "
            }
            lines += await renderListItem(item, marker: marker, baseDirectory: baseDirectory, indent: indent)
        }
        return lines
    }

    private func renderListItem(
        _ item: Markdown.ListItem,
        marker: String,
        baseDirectory: URL,
        indent: Int
    ) async -> [String] {
        let prefix = String(repeating: "  ", count: indent)
        var children = Array(item.children)
        var lines: [String] = []

        if let first = children.first as? Paragraph {
            let content = await renderInlineChildren(first, baseDirectory: baseDirectory)
            let contentLines = content.components(separatedBy: "\n").filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let firstLine = contentLines.first {
                lines.append(prefix + marker + normalizeImportedLinePrefix(firstLine.trimmingCharacters(in: .whitespacesAndNewlines)))
                let continuation = String(repeating: "  ", count: indent + 1)
                for extraLine in contentLines.dropFirst() {
                    lines.append(continuation + normalizeImportedLinePrefix(extraLine.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            } else {
                lines.append(prefix + marker.trimmingCharacters(in: .whitespaces))
            }
            children.removeFirst()
        } else {
            lines.append(prefix + marker.trimmingCharacters(in: .whitespaces))
        }

        for child in children {
            lines += await renderMarkdownBlock(child, baseDirectory: baseDirectory, indent: indent + 1)
        }
        return lines
    }

    private func renderInlineChildren(_ markup: Markup, baseDirectory: URL) async -> String {
        var result = ""
        for child in markup.children {
            result += await renderInline(child, baseDirectory: baseDirectory)
        }
        return result
    }

    private func renderInline(_ markup: Markup, baseDirectory: URL) async -> String {
        switch markup {
        case let text as Text:
            return JotMarkupLiteral.escapeIfNeeded(text.string)
        case let code as InlineCode:
            return "[[ic]]\(JotMarkupLiteral.escapeIfNeeded(code.code))[[/ic]]"
        case is SoftBreak:
            return "\n"
        case is LineBreak:
            return "\n"
        case let html as InlineHTML:
            let raw = html.rawHTML
            if raw.lowercased().hasPrefix("<br") {
                return "\n"
            }
            return JotMarkupLiteral.escapeIfNeeded(raw)
        case let strong as Strong:
            return "[[b]]\(await renderInlineChildren(strong, baseDirectory: baseDirectory))[[/b]]"
        case let emphasis as Emphasis:
            return "[[i]]\(await renderInlineChildren(emphasis, baseDirectory: baseDirectory))[[/i]]"
        case let strike as Strikethrough:
            return "[[s]]\(await renderInlineChildren(strike, baseDirectory: baseDirectory))[[/s]]"
        case let link as Link:
            let destination = (link.destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = Self.markdownPlainText(link)
            guard !destination.isEmpty else { return JotMarkupLiteral.escapeIfNeeded(label) }
            guard Self.isSafeTokenField(destination), Self.isSafeTokenField(label) else {
                return JotMarkupLiteral.escapeIfNeeded("\(JotMarkupLiteral.replacingRawTokens(in: label)) (\(destination))")
            }
            return label == destination ? "[[link|\(destination)]]" : "[[link|\(destination)|\(label)]]"
        case let image as Image:
            return await renderMarkdownImage(image, baseDirectory: baseDirectory)
        default:
            return JotMarkupLiteral.escapeIfNeeded(Self.markdownPlainText(markup))
        }
    }

    private func renderMarkdownImage(_ image: Image, baseDirectory: URL) async -> String {
        let altText = Self.markdownPlainText(image)
        guard let source = image.source, !source.isEmpty else {
            return JotMarkupLiteral.escapeIfNeeded(altText)
        }

        let imageURL: URL?
        if let url = URL(string: source), url.scheme != nil {
            imageURL = url
        } else {
            imageURL = canonicalFileURLIfUnderBase(relativePath: source, baseDir: baseDirectory)
        }

        if let imageURL, let filename = await ImageStorageManager.shared.saveImage(from: imageURL) {
            return "[[image|||\(filename)]]"
        }

        let readable = altText.isEmpty ? source : altText
        return JotMarkupLiteral.escapeIfNeeded(readable)
    }

    private static func isSafeTokenField(_ field: String) -> Bool {
        !field.contains("|") && !field.contains("]]") && !field.contains("\n")
    }

    private func renderMarkdownTable(_ table: Table) -> String {
        var rows: [[String]] = []
        let header = renderMarkdownTableRow(table.head)
        if !header.isEmpty { rows.append(header) }
        for child in table.body.children {
            guard let row = child as? Table.Row else { continue }
            rows.append(renderMarkdownTableRow(row))
        }

        let columnCount = max(table.maxColumnCount, rows.map(\.count).max() ?? 1)
        let normalizedRows = rows.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        let widths = Self.estimatedMarkdownTableColumnWidths(normalizedRows, columnCount: columnCount)
        return NoteTableData(columns: columnCount, cells: normalizedRows, columnWidths: widths, wrapText: true).serialize()
    }

    private func renderMarkdownTableRow(_ row: Markup) -> [String] {
        row.children.compactMap { child in
            guard let cell = child as? Table.Cell else { return nil }
            return Self.markdownPlainText(cell)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func estimatedMarkdownTableColumnWidths(_ rows: [[String]], columnCount: Int) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        return (0..<columnCount).map { column in
            let maxLength = rows.map { row in
                row.indices.contains(column) ? row[column].count : 0
            }.max() ?? 0
            return min(max(CGFloat(maxLength * 8 + 40), 88), 520)
        }
    }

    private static func markdownPlainText(_ markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return JotMarkupLiteral.replacingRawTokens(in: text.string)
        case let code as InlineCode:
            return code.code
        case is SoftBreak:
            return " "
        case is LineBreak:
            return "\n"
        case let html as InlineHTML:
            return html.rawHTML
        case let html as HTMLBlock:
            return html.rawHTML
        case let codeBlock as CodeBlock:
            return codeBlock.code
        default:
            return markup.children.map { markdownPlainText($0) }.joined()
        }
    }

    private func normalizeImportedMarkdownLines(_ lines: [String]) -> [String] {
        var normalized: [String] = []
        var previousWasDivider = false

        for rawLine in lines {
            let line = Self.trimmingTrailingHorizontalWhitespace(rawLine)
            let semanticLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !semanticLine.isEmpty else { continue }
            if semanticLine == "[[divider]]" {
                guard !previousWasDivider else { continue }
                previousWasDivider = true
            } else {
                previousWasDivider = false
            }
            normalized.append(line)
        }

        while normalized.first == "[[divider]]" {
            normalized.removeFirst()
        }
        while normalized.last == "[[divider]]" {
            normalized.removeLast()
        }
        return normalized
    }

    private static func trimmingTrailingHorizontalWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous] == " " || text[previous] == "\t" else { break }
            end = previous
        }
        return String(text[..<end]).trimmingCharacters(in: .newlines)
    }

    private func normalizeImportedLinePrefix(_ line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(leading.count)
        if rest.hasPrefix("-> ") {
            return String(leading) + "[[arrow]] " + String(rest.dropFirst(3))
        }
        if rest.hasPrefix("=> ") {
            return String(leading) + "\u{21D2} " + String(rest.dropFirst(3))
        }
        return line
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
                    let label = JotMarkupLiteral.replacingRawTokens(in: substring)
                    if !Self.isSafeTokenField(urlString) || !Self.isSafeTokenField(label) {
                        let readable = label.isEmpty ? urlString : "\(label) (\(urlString))"
                        paraContent += JotMarkupLiteral.escapeIfNeeded(readable)
                    } else if label == urlString || label.isEmpty {
                        paraContent += "[[link|\(urlString)]]"
                    } else {
                        paraContent += "[[link|\(urlString)|\(label)]]"
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
                var wrapped = JotMarkupLiteral.escapeIfNeeded(substring)
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

    /// Markdown blank lines separate blocks but are not extra vertical space in Jot.
    /// Code/tables/callouts serialize internal newlines as escaped sequences inside tags,
    /// so collapsing `\n{2,}` → `\n` here does not strip real blank lines inside those blocks.
    /// Internal so `@testable` unit tests can assert normalization without disk I/O.
    func collapseMarkdownParagraphSeparators(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\n{2,}") else { return text }
        var collapsed = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "\n"
        )
        // A single leading newline still creates an empty first paragraph; trim one.
        if collapsed.hasPrefix("\n") {
            collapsed.removeFirst()
        }
        return collapsed
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

    private static func normalizedMarkdownCodeBlockBody(_ raw: String) -> String {
        guard raw.hasSuffix("\n") else { return raw }
        return String(raw.dropLast())
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

}
