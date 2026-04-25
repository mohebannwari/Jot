import CoreGraphics
import Foundation

@MainActor
struct NoteMarkupHTMLRenderer {

    enum Context {
        case quickLook
        case export
    }

    struct Options {
        let context: Context
        let embedStoredImages: Bool

        init(context: Context) {
            self.context = context
            self.embedStoredImages = context == .export
        }
    }

    private enum Alignment: String {
        case center
        case right
        case justify
    }

    private enum ListContainerKind: Equatable {
        case ordered
        case bullet
        case todo
    }

    private struct ListItem {
        let containerKind: ListContainerKind
        let indent: Int
        let alignment: Alignment?
        let value: Int?
        let isChecked: Bool
        let contentHTML: String
    }

    static func renderFragment(_ content: String, context: Context) -> String {
        let cleanContent = NoteDetailView.stripAIBlock(content).content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return renderBlocks(cleanContent, options: Options(context: context))
    }

    static func sharedStyles(for context: Context) -> String {
        let contextStyles: String = switch context {
        case .quickLook:
            """
            .note-markup {
              --note-markup-fg: var(--fg);
              --note-markup-muted: var(--fg2);
              --note-markup-border: var(--div-clr);
              --note-markup-surface: var(--attach-bg);
              --note-markup-surface-strong: rgba(96, 141, 250, 0.12);
              --note-markup-link: #608dfa;
              --note-markup-code-bg: rgba(26, 26, 26, 0.06);
              --note-markup-code-border: rgba(26, 26, 26, 0.08);
            }
            @media (prefers-color-scheme: dark) {
              .note-markup {
                --note-markup-surface-strong: rgba(96, 141, 250, 0.18);
                --note-markup-code-bg: rgba(255, 255, 255, 0.08);
                --note-markup-code-border: rgba(255, 255, 255, 0.08);
              }
            }
            """
        case .export:
            """
            .note-markup {
              --note-markup-fg: #1a1a1a;
              --note-markup-muted: rgba(26, 26, 26, 0.7);
              --note-markup-border: rgba(0, 0, 0, 0.12);
              --note-markup-surface: #f5f5f5;
              --note-markup-surface-strong: rgba(96, 141, 250, 0.12);
              --note-markup-link: #2563eb;
              --note-markup-code-bg: rgba(26, 26, 26, 0.06);
              --note-markup-code-border: rgba(26, 26, 26, 0.08);
            }
            """
        }

        return contextStyles + """
        .note-markup {
          color: var(--note-markup-fg);
          font-size: 15px;
          line-height: 1.65;
        }
        .note-markup > :first-child { margin-top: 0; }
        .note-markup > :last-child { margin-bottom: 0; }
        .note-markup p {
          margin: 0 0 8px;
          word-break: break-word;
        }
        .note-markup .empty-paragraph {
          min-height: 0.8em;
          margin: 0 0 8px;
        }
        .note-markup h2,
        .note-markup h3,
        .note-markup h4 {
          color: var(--note-markup-fg);
          font-weight: 600;
          margin: 22px 0 8px;
          letter-spacing: 0;
        }
        .note-markup h2 { font-size: 20px; }
        .note-markup h3 { font-size: 17px; }
        .note-markup h4 { font-size: 15px; }
        .note-markup a {
          color: var(--note-markup-link);
          text-decoration: none;
        }
        .note-markup a:hover { text-decoration: underline; }
        .note-markup code {
          font-family: 'SF Mono', Menlo, Monaco, monospace;
          font-size: 0.92em;
          background: var(--note-markup-code-bg);
          border: 1px solid var(--note-markup-code-border);
          border-radius: 6px;
          padding: 1px 6px;
        }
        .note-markup pre {
          margin: 10px 0 14px;
          padding: 14px 16px;
          border-radius: 12px;
          background: var(--note-markup-surface);
          overflow-x: auto;
          border: 1px solid var(--note-markup-border);
        }
        .note-markup pre code {
          background: transparent;
          border: 0;
          padding: 0;
          font-size: 13px;
          line-height: 1.5;
        }
        .note-markup .code-block-label {
          display: inline-block;
          margin-bottom: 8px;
          font-size: 11px;
          font-weight: 600;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--note-markup-muted);
        }
        .note-markup .code-block {
          margin: 10px 0 14px;
        }
        .note-markup .code-block pre {
          margin: 0;
        }
        .note-markup blockquote {
          margin: 12px 0;
          padding: 4px 0 4px 16px;
          border-left: 3px solid var(--note-markup-border);
          color: var(--note-markup-muted);
        }
        .note-markup blockquote p:last-child { margin-bottom: 0; }
        .note-markup mark {
          border-radius: 4px;
          padding: 1px 3px;
        }
        .note-markup .note-divider {
          border: 0;
          height: 1px;
          background: var(--note-markup-border);
          margin: 16px 0;
        }
        .note-markup .attachment-chip {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          min-height: 28px;
          padding: 4px 10px;
          border-radius: 999px;
          background: var(--note-markup-surface-strong);
          border: 1px solid var(--note-markup-border);
          color: var(--note-markup-fg);
          font-size: 13px;
          font-weight: 500;
          text-decoration: none;
          vertical-align: middle;
        }
        .note-markup .attachment-chip-label {
          overflow-wrap: anywhere;
        }
        .note-markup .attachment-chip-icon {
          font-size: 12px;
          color: var(--note-markup-muted);
        }
        .note-markup .image-block {
          margin: 12px 0 16px;
        }
        .note-markup .image-block img {
          max-width: 100%;
          height: auto;
          border-radius: 12px;
          border: 1px solid var(--note-markup-border);
          display: block;
        }
        .note-markup .callout {
          margin: 12px 0 16px;
          padding: 12px 14px;
          border-radius: 14px;
          background: var(--note-markup-surface);
          border: 1px solid var(--note-markup-border);
        }
        .note-markup .callout-label {
          margin-bottom: 8px;
          font-size: 12px;
          font-weight: 600;
          letter-spacing: 0.02em;
          color: var(--note-markup-muted);
          text-transform: capitalize;
        }
        .note-markup .callout.callout-warning {
          border-color: rgba(234, 179, 8, 0.4);
        }
        .note-markup .callout.callout-important {
          border-color: rgba(239, 68, 68, 0.35);
        }
        .note-markup .callout.callout-tip,
        .note-markup .callout.callout-info,
        .note-markup .callout.callout-note {
          border-color: rgba(96, 141, 250, 0.28);
        }
        .note-markup .table-wrapper {
          margin: 12px 0 16px;
          overflow-x: auto;
          border: 1px solid var(--note-markup-border);
          border-radius: 14px;
          background: var(--note-markup-surface);
        }
        .note-markup .cards-section {
          margin: 12px 0 16px;
          overflow-x: auto;
          padding-bottom: 4px;
        }
        .note-markup .cards-grid {
          display: flex;
          align-items: flex-start;
          gap: 12px;
          min-width: max-content;
        }
        .note-markup .cards-column {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        .note-markup .cards-card {
          flex: 0 0 auto;
          padding: 16px;
          border-radius: 22px;
          border: 2px solid var(--card-border-light);
          background: var(--card-fill-light);
          color: var(--note-markup-fg);
          overflow: hidden;
        }
        @media (prefers-color-scheme: dark) {
          .note-markup .cards-card {
            border-color: var(--card-border-dark);
            background: var(--card-fill-dark);
          }
        }
        .note-markup .cards-card > :first-child,
        .note-markup .tabs-pane-content > :first-child {
          margin-top: 0;
        }
        .note-markup .cards-card > :last-child,
        .note-markup .tabs-pane-content > :last-child {
          margin-bottom: 0;
        }
        .note-markup .tabs-section {
          margin: 12px 0 16px;
          border-radius: 22px;
          border: 1px solid var(--note-markup-border);
          background: var(--note-markup-surface);
          overflow: hidden;
        }
        .note-markup .tabs-bar {
          display: flex;
          align-items: center;
          gap: 8px;
          padding: 8px;
          border-bottom: 1px solid var(--note-markup-border);
          overflow-x: auto;
        }
        .note-markup .tabs-chip {
          flex: 0 0 auto;
          display: inline-flex;
          align-items: center;
          min-height: 32px;
          padding: 8px 12px;
          border-radius: 12px;
          border: 1px solid var(--note-markup-border);
          background: transparent;
          color: var(--note-markup-muted);
          font-size: 12px;
          font-weight: 600;
          letter-spacing: 0;
        }
        .note-markup .tabs-chip.is-active {
          border-color: var(--tab-accent-border, var(--note-markup-border));
          background: var(--tab-accent-fill, var(--note-markup-surface-strong));
          color: var(--tab-accent-fg, var(--note-markup-fg));
        }
        .note-markup .tabs-pane-content {
          padding: 16px;
        }
        .note-markup table {
          width: 100%;
          border-collapse: collapse;
          table-layout: fixed;
        }
        .note-markup td,
        .note-markup th {
          padding: 10px 12px;
          border-bottom: 1px solid var(--note-markup-border);
          border-right: 1px solid var(--note-markup-border);
          text-align: left;
          vertical-align: top;
          word-break: normal;
          overflow-wrap: break-word;
          white-space: normal;
        }
        .note-markup tr:last-child td,
        .note-markup tr:last-child th {
          border-bottom: 0;
        }
        .note-markup td:last-child,
        .note-markup th:last-child {
          border-right: 0;
        }
        .note-markup .note-list {
          margin: 8px 0 12px;
          padding-left: 24px;
        }
        .note-markup .note-list li {
          margin: 4px 0;
        }
        .note-markup .note-list li > .list-item-content,
        .note-markup .note-list li > .todo-content {
          display: inline;
        }
        .note-markup .todo-list {
          list-style: none;
          padding-left: 0;
        }
        .note-markup .todo-list li {
          position: relative;
          padding-left: 28px;
        }
        .note-markup .todo-checkbox {
          position: absolute;
          left: 0;
          top: 0;
          color: var(--note-markup-muted);
        }
        .note-markup .todo-item.checked .todo-content {
          text-decoration: line-through;
          color: var(--note-markup-muted);
        }
        """
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func sanitizeURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/") || trimmed.hasPrefix("#") {
            return trimmed
        }

        let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel"]
        if let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() {
            return allowedSchemes.contains(scheme) ? trimmed : "#"
        }

        if !trimmed.contains(":") {
            return trimmed
        }

        return "#"
    }

    private static func renderBlocks(_ content: String, options: Options) -> String {
        guard !content.isEmpty else { return "" }

        let lines = content.components(separatedBy: "\n")
        var index = 0
        var blocks: [String] = []

        while index < lines.count {
            if let tableHTML = renderTableBlock(from: lines, start: &index) {
                blocks.append(tableHTML)
                continue
            }
            if let codeBlockHTML = renderCodeBlock(from: lines, start: &index) {
                blocks.append(codeBlockHTML)
                continue
            }
            if let legacyCodeHTML = renderLegacyCodeBlock(from: lines, start: &index) {
                blocks.append(legacyCodeHTML)
                continue
            }
            if let calloutHTML = renderCalloutBlock(from: lines, start: &index, options: options) {
                blocks.append(calloutHTML)
                continue
            }
            if let cardsHTML = renderCardsBlock(from: lines, start: &index, options: options) {
                blocks.append(cardsHTML)
                continue
            }
            if let tabsHTML = renderTabsBlock(from: lines, start: &index, options: options) {
                blocks.append(tabsHTML)
                continue
            }
            if let quoteHTML = renderQuoteBlock(from: lines, start: &index, options: options) {
                blocks.append(quoteHTML)
                continue
            }
            if let listHTML = renderListBlock(from: lines, start: &index, options: options) {
                blocks.append(listHTML)
                continue
            }

            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed == "[[divider]]" {
                blocks.append("<hr class=\"note-divider\">")
            } else if let quoteLineBlocks = renderLeadingQuoteLine(rawLine, options: options) {
                blocks.append(contentsOf: quoteLineBlocks)
            } else if trimmed.isEmpty {
                blocks.append("<p class=\"empty-paragraph\"></p>")
            } else {
                blocks.append(renderStandardLine(rawLine, options: options))
            }

            index += 1
        }

        return blocks.joined(separator: "\n")
    }

    private static func renderStandardLine(_ rawLine: String, options: Options) -> String {
        let (line, alignment) = unwrapAlignment(from: rawLine)

        if line.hasPrefix("[[h1]]"), line.hasSuffix("[[/h1]]") {
            let inner = String(line.dropFirst(6).dropLast(7))
            return "<h2\(alignmentStyle(alignment))>\(renderInline(inner, options: options))</h2>"
        }
        if line.hasPrefix("[[h2]]"), line.hasSuffix("[[/h2]]") {
            let inner = String(line.dropFirst(6).dropLast(7))
            return "<h3\(alignmentStyle(alignment))>\(renderInline(inner, options: options))</h3>"
        }
        if line.hasPrefix("[[h3]]"), line.hasSuffix("[[/h3]]") {
            let inner = String(line.dropFirst(6).dropLast(7))
            return "<h4\(alignmentStyle(alignment))>\(renderInline(inner, options: options))</h4>"
        }

        return "<p\(alignmentStyle(alignment))>\(renderInline(line, options: options))</p>"
    }

    private static func renderQuoteBlock(from lines: [String], start: inout Int, options: Options) -> String? {
        var paragraphs: [String] = []
        var index = start

        while index < lines.count {
            let (line, alignment) = unwrapAlignment(from: lines[index])
            guard line.hasPrefix("[[quote]]"), line.hasSuffix("[[/quote]]") else { break }

            let inner = String(line.dropFirst(9).dropLast(10))
            paragraphs.append("<p\(alignmentStyle(alignment))>\(renderInline(inner, options: options))</p>")
            index += 1
        }

        guard !paragraphs.isEmpty else { return nil }
        start = index
        return "<blockquote>\(paragraphs.joined(separator: "\n"))</blockquote>"
    }

    private static func renderListBlock(from lines: [String], start: inout Int, options: Options) -> String? {
        var items: [ListItem] = []
        var index = start

        while index < lines.count, let item = parseListItem(from: lines[index], options: options) {
            items.append(item)
            index += 1
        }

        guard !items.isEmpty else { return nil }
        start = index
        return renderList(items)
    }

    private static func parseListItem(from rawLine: String, options: Options) -> ListItem? {
        let (line, alignment) = unwrapAlignment(from: rawLine)
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let indent = leading.reduce(0) { partial, char in
            partial + (char == "\t" ? 2 : 1)
        } / 2
        let stripped = String(line.dropFirst(leading.count))

        if stripped.hasPrefix("[x] ") {
            return ListItem(
                containerKind: .todo,
                indent: indent,
                alignment: alignment,
                value: nil,
                isChecked: true,
                contentHTML: renderInline(String(stripped.dropFirst(4)), options: options)
            )
        }
        if stripped == "[x]" {
            return ListItem(
                containerKind: .todo,
                indent: indent,
                alignment: alignment,
                value: nil,
                isChecked: true,
                contentHTML: ""
            )
        }
        if stripped.hasPrefix("[ ] ") {
            return ListItem(
                containerKind: .todo,
                indent: indent,
                alignment: alignment,
                value: nil,
                isChecked: false,
                contentHTML: renderInline(String(stripped.dropFirst(4)), options: options)
            )
        }
        if stripped == "[ ]" {
            return ListItem(
                containerKind: .todo,
                indent: indent,
                alignment: alignment,
                value: nil,
                isChecked: false,
                contentHTML: ""
            )
        }
        if stripped.hasPrefix("• ") || stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("+ ") {
            return ListItem(
                containerKind: .bullet,
                indent: indent,
                alignment: alignment,
                value: nil,
                isChecked: false,
                contentHTML: renderInline(String(stripped.dropFirst(2)), options: options)
            )
        }
        if stripped.hasPrefix("[[ol|"), let closeRange = stripped.range(of: "]]") {
            let numberString = String(stripped[stripped.index(stripped.startIndex, offsetBy: 5)..<closeRange.lowerBound])
            let value = Int(numberString) ?? 1
            let body = String(stripped[closeRange.upperBound...])
            return ListItem(
                containerKind: .ordered,
                indent: indent,
                alignment: alignment,
                value: value,
                isChecked: false,
                contentHTML: renderInline(body, options: options)
            )
        }

        return nil
    }

    private static func renderList(_ items: [ListItem]) -> String {
        var html = ""
        var stack: [ListContainerKind] = []
        var openItemFlags: [Bool] = []

        func openList(_ kind: ListContainerKind) {
            html += openingListTag(for: kind)
            stack.append(kind)
            openItemFlags.append(false)
        }

        func closeCurrentItemIfNeeded() {
            guard !openItemFlags.isEmpty, openItemFlags[openItemFlags.count - 1] else { return }
            html += "</li>"
            openItemFlags[openItemFlags.count - 1] = false
        }

        func closeList() {
            closeCurrentItemIfNeeded()
            guard let kind = stack.popLast() else { return }
            _ = openItemFlags.popLast()
            html += closingListTag(for: kind)
        }

        for rawItem in items {
            let desiredDepth = max(1, min(rawItem.indent + 1, stack.count + 1))

            while stack.count > desiredDepth {
                closeList()
            }

            if stack.count == desiredDepth {
                if let currentKind = stack.last, currentKind != rawItem.containerKind {
                    closeList()
                } else {
                    closeCurrentItemIfNeeded()
                }
            }

            while stack.count < desiredDepth {
                openList(rawItem.containerKind)
            }

            if stack.isEmpty {
                openList(rawItem.containerKind)
            } else if stack.last != rawItem.containerKind {
                closeList()
                openList(rawItem.containerKind)
            }

            html += openingListItemTag(for: rawItem)
            openItemFlags[openItemFlags.count - 1] = true
        }

        while !stack.isEmpty {
            closeList()
        }

        return html
    }

    private static func openingListTag(for kind: ListContainerKind) -> String {
        switch kind {
        case .ordered:
            return "<ol class=\"note-list ordered-list\">"
        case .bullet:
            return "<ul class=\"note-list bullet-list\">"
        case .todo:
            return "<ul class=\"note-list todo-list\">"
        }
    }

    private static func closingListTag(for kind: ListContainerKind) -> String {
        switch kind {
        case .ordered:
            return "</ol>"
        case .bullet, .todo:
            return "</ul>"
        }
    }

    private static func openingListItemTag(for item: ListItem) -> String {
        let style = alignmentStyle(item.alignment)

        switch item.containerKind {
        case .ordered:
            let valueAttribute = item.value.map { " value=\"\($0)\"" } ?? ""
            return "<li\(valueAttribute)\(style)><span class=\"list-item-content\">\(item.contentHTML)</span>"
        case .bullet:
            return "<li\(style)><span class=\"list-item-content\">\(item.contentHTML)</span>"
        case .todo:
            let checkedClass = item.isChecked ? " checked" : ""
            let symbol = item.isChecked ? "&#9745;" : "&#9744;"
            return "<li class=\"todo-item\(checkedClass)\"\(style)><span class=\"todo-checkbox\" aria-hidden=\"true\">\(symbol)</span><span class=\"todo-content\">\(item.contentHTML)</span>"
        }
    }

    private static func renderTableBlock(from lines: [String], start: inout Int) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[table|",
            closeMarker: "[[/table]]"
        ) else { return nil }

        start = block.nextIndex

        guard let table = NoteTableData.deserialize(from: block.blockText) else {
            return attachmentChip(icon: "Table", label: "Unsupported table")
        }

        let widths = normalizedColumnWidths(for: table)
        let colgroup = "<colgroup>"
            + widths.map { "<col style=\"width:\(Int(ceil($0)))px\">" }.joined()
            + "</colgroup>"
        let minWidth = Int(ceil(widths.reduce(0, +)))

        let rows = table.cells.enumerated().map { rowIndex, row in
            let tag = rowIndex == 0 ? "th" : "td"
            let columns = row.map { cell in
                "<\(tag)>\(escapeHTML(cell).replacingOccurrences(of: "\n", with: "<br>"))</\(tag)>"
            }.joined()
            return "<tr>\(columns)</tr>"
        }.joined()

        return "<div class=\"table-wrapper\"><table style=\"min-width:\(minWidth)px\">\(colgroup)\(rows)</table></div>"
    }

    private static func normalizedColumnWidths(for table: NoteTableData) -> [CGFloat] {
        let fallback = Array(repeating: NoteTableData.defaultColumnWidth, count: table.columns)
        guard table.columnWidths.count == table.columns else { return fallback }
        return table.columnWidths.map { max(64, $0) }
    }

    private static func renderCodeBlock(from lines: [String], start: inout Int) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[codeblock|",
            closeMarker: "[[/codeblock]]"
        ) else { return nil }

        start = block.nextIndex

        guard let codeBlock = CodeBlockData.deserialize(from: block.blockText) else {
            return attachmentChip(icon: "Code", label: "Unsupported code block")
        }

        let language = CodeBlockData.displayName(for: codeBlock.language)
        let escapedCode = escapeHTML(codeBlock.code)
        let labelHTML = language.lowercased() == "plaintext"
            ? ""
            : "<div class=\"code-block-label\">\(escapeHTML(language))</div>"

        return "<div class=\"code-block\">\(labelHTML)<pre><code>\(escapedCode)</code></pre></div>"
    }

    private static func renderLegacyCodeBlock(from lines: [String], start: inout Int) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[code]]",
            closeMarker: "[[/code]]"
        ) else { return nil }

        start = block.nextIndex

        guard let openRange = block.blockText.range(of: "[[code]]"),
              let closeRange = block.blockText.range(of: "[[/code]]") else {
            return attachmentChip(icon: "Code", label: "Unsupported code block")
        }

        let code = String(block.blockText[openRange.upperBound..<closeRange.lowerBound])
        let escapedCode = escapeHTML(code)
        return "<pre><code>\(escapedCode)</code></pre>"
    }

    private static func renderCalloutBlock(from lines: [String], start: inout Int, options: Options) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[callout|",
            closeMarker: "[[/callout]]"
        ) else { return nil }

        start = block.nextIndex

        guard let callout = CalloutData.deserialize(from: block.blockText) else {
            return attachmentChip(icon: "Callout", label: "Unsupported callout")
        }

        let label = escapeHTML(callout.type.rawValue.capitalized)
        let body = renderBlocks(callout.content, options: options)

        return """
        <section class="callout callout-\(callout.type.rawValue)">
          <div class="callout-label">\(label)</div>
          <div class="callout-content">\(body)</div>
        </section>
        """
    }

    private static func renderCardsBlock(from lines: [String], start: inout Int, options: Options) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[cards|",
            closeMarker: "[[/cards]]"
        ) else { return nil }

        start = block.nextIndex

        guard let cards = CardSectionData.deserialize(from: block.blockText) else {
            return attachmentChip(icon: "Cards", label: "Unsupported cards block")
        }

        let columnsHTML = cards.columns.map { column in
            let cardsHTML = column.map { card in
                let body = renderBlocks(card.content, options: options)
                return """
                <section class="cards-card" \(cardStyleAttributes(card))>
                  \(body)
                </section>
                """
            }.joined(separator: "\n")
            return "<div class=\"cards-column\">\(cardsHTML)</div>"
        }.joined(separator: "\n")

        return """
        <section class="cards-section">
          <div class="cards-grid">\(columnsHTML)</div>
        </section>
        """
    }

    private static func renderTabsBlock(from lines: [String], start: inout Int, options: Options) -> String? {
        guard let block = gatherDelimitedBlock(
            from: lines,
            start: start,
            openPrefix: "[[tabs|",
            closeMarker: "[[/tabs]]"
        ) else { return nil }

        start = block.nextIndex

        guard let tabs = TabsContainerData.deserialize(from: block.blockText),
              tabs.panes.indices.contains(tabs.activeIndex) else {
            return attachmentChip(icon: "Tabs", label: "Unsupported tabs block")
        }

        let tabsBarHTML = tabs.panes.enumerated().map { index, pane in
            let classes = index == tabs.activeIndex ? "tabs-chip is-active" : "tabs-chip"
            return "<span class=\"\(classes)\"\(tabStyleAttributes(colorHex: pane.colorHex))>\(escapeHTML(pane.name))</span>"
        }.joined(separator: "\n")
        let activePaneBody = renderBlocks(tabs.panes[tabs.activeIndex].content, options: options)

        return """
        <section class="tabs-section">
          <div class="tabs-bar">\(tabsBarHTML)</div>
          <div class="tabs-pane-content">\(activePaneBody)</div>
        </section>
        """
    }

    private static func gatherDelimitedBlock(
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

    private static func renderInline(_ text: String, options: Options) -> String {
        guard !text.isEmpty else { return "" }

        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            let remaining = text[index...]

            if let literal = JotMarkupLiteral.consumeToken(in: text, at: index) {
                output += escapeHTML(literal.decoded)
                index = literal.end
                continue
            }

            if remaining.hasPrefix("[[b]]") {
                output += "<strong>"
                index = text.index(index, offsetBy: 5)
                continue
            }
            if remaining.hasPrefix("[[/b]]") {
                output += "</strong>"
                index = text.index(index, offsetBy: 6)
                continue
            }
            if remaining.hasPrefix("[[i]]") {
                output += "<em>"
                index = text.index(index, offsetBy: 5)
                continue
            }
            if remaining.hasPrefix("[[/i]]") {
                output += "</em>"
                index = text.index(index, offsetBy: 6)
                continue
            }
            if remaining.hasPrefix("[[u]]") {
                output += "<u>"
                index = text.index(index, offsetBy: 5)
                continue
            }
            if remaining.hasPrefix("[[/u]]") {
                output += "</u>"
                index = text.index(index, offsetBy: 6)
                continue
            }
            if remaining.hasPrefix("[[s]]") {
                output += "<s>"
                index = text.index(index, offsetBy: 5)
                continue
            }
            if remaining.hasPrefix("[[/s]]") {
                output += "</s>"
                index = text.index(index, offsetBy: 6)
                continue
            }
            if remaining.hasPrefix("[[ic]]") {
                let contentStart = text.index(index, offsetBy: 6)
                if let close = text[contentStart...].range(of: "[[/ic]]") {
                    let inner = String(text[contentStart..<close.lowerBound])
                    output += "<code>\(renderInlineCodeLiteral(inner))</code>"
                    index = close.upperBound
                } else {
                    output += escapeHTML("[[ic]]")
                    index = contentStart
                }
                continue
            }
            if remaining.hasPrefix("[[/ic]]") {
                output += escapeHTML("[[/ic]]")
                index = text.index(index, offsetBy: 7)
                continue
            }
            if remaining.hasPrefix("[[/color]]") {
                output += "</span>"
                index = text.index(index, offsetBy: 10)
                continue
            }
            if remaining.hasPrefix("[[/hl]]") {
                output += "</mark>"
                index = text.index(index, offsetBy: 7)
                continue
            }
            if remaining.hasPrefix("[[arrow]]") {
                output += "<span class=\"inline-arrow\" aria-hidden=\"true\">&rarr;</span>"
                index = text.index(index, offsetBy: 9)
                continue
            }
            if remaining.hasPrefix("[[color|"), let close = remaining.range(of: "]]") {
                let hex = String(remaining[remaining.index(remaining.startIndex, offsetBy: 8)..<close.lowerBound])
                let sanitizedHex = sanitizeColorHex(hex) ?? "1a1a1a"
                output += "<span style=\"color:#\(sanitizedHex)\">"
                index = close.upperBound
                continue
            }
            if remaining.hasPrefix("[[hl|"), let close = remaining.range(of: "]]") {
                let payload = String(remaining[remaining.index(remaining.startIndex, offsetBy: 5)..<close.lowerBound])
                let hex = payload.components(separatedBy: "|").first ?? ""
                let sanitizedHex = sanitizeColorHex(hex) ?? "fff59d"
                output += "<mark style=\"background-color:#\(sanitizedHex)\">"
                index = close.upperBound
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
                output += renderImageToken(body, options: options)
                index = close.upperBound
                continue
            }
            if remaining.hasPrefix(MapBlockData.markupPrefix), let close = remaining.range(of: "]]") {
                let token = String(remaining[..<close.upperBound])
                output += renderMapToken(token)
                index = close.upperBound
                continue
            }

            output += escapeHTML(String(text[index]))
            index = text.index(after: index)
        }

        return output
    }

    private static func renderInlineCodeLiteral(_ text: String) -> String {
        escapeHTML(JotMarkupLiteral.replacingRawTokens(in: text))
    }

    private static func renderLinkToken(_ body: String) -> String {
        let parts = body.components(separatedBy: "|")
        guard let url = parts.first else { return escapeHTML("[[link|\(body)]]") }
        let label = parts.count > 1 ? parts[1] : url
        let sanitizedURL = escapeHTML(sanitizeURL(url))
        return "<a href=\"\(sanitizedURL)\">\(escapeHTML(label))</a>"
    }

    private static func renderNoteLinkToken(_ body: String) -> String {
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let title = parts.count == 2 ? String(parts[1]) : "Mentioned Note"
        return attachmentChip(icon: "@", label: title)
    }

    private static func renderWebClipToken(_ body: String) -> String {
        let parts = body.components(separatedBy: "|")
        let title = parts.first(where: { !$0.isEmpty }) ?? "Web Clip"
        let url = parts.count >= 3 ? parts[2] : (parts.last ?? "#")
        let sanitizedURL = escapeHTML(sanitizeURL(url))
        return "<a class=\"attachment-chip\" href=\"\(sanitizedURL)\"><span class=\"attachment-chip-icon\">Link</span><span class=\"attachment-chip-label\">\(escapeHTML(title))</span></a>"
    }

    private static func renderLinkCardToken(_ body: String) -> String {
        let parts = body.components(separatedBy: "|")
        let title = parts.first(where: { !$0.isEmpty }) ?? "Link"
        let url = parts.count >= 3 ? parts[2] : (parts.last ?? "#")
        let sanitizedURL = escapeHTML(sanitizeURL(url))
        return "<a class=\"attachment-chip\" href=\"\(sanitizedURL)\"><span class=\"attachment-chip-icon\">Link</span><span class=\"attachment-chip-label\">\(escapeHTML(title))</span></a>"
    }

    private static func renderFileLinkToken(_ body: String) -> String {
        let parts = body.components(separatedBy: "|")
        let displayName = parts.count >= 2 ? parts[1] : (parts.first ?? "File")
        return attachmentChip(icon: "File", label: displayName)
    }

    private static func renderFileToken(_ body: String) -> String {
        let parts = body.components(separatedBy: "|")
        let originalName: String
        if parts.count >= 3 {
            originalName = parts[2]
        } else if let fallback = parts.last {
            originalName = fallback
        } else {
            originalName = "File"
        }
        return attachmentChip(icon: "File", label: originalName)
    }

    private static func renderImageToken(_ body: String, options: Options) -> String {
        let parts = body.components(separatedBy: "|||")
        let filename = parts.first ?? ""

        if options.embedStoredImages,
           let imageURL = ImageStorageManager.shared.getImageURL(for: filename),
           let imageData = try? Data(contentsOf: imageURL) {
            let mimeType = imageMimeType(for: imageURL)
            let base64 = imageData.base64EncodedString()
            return "<figure class=\"image-block\"><img src=\"data:\(mimeType);base64,\(base64)\" alt=\"Image\"></figure>"
        }

        return attachmentChip(icon: "Image", label: "Image")
    }

    private static func renderMapToken(_ token: String) -> String {
        let title = MapBlockData.deserialize(from: token)?.displayTitle ?? "Map"
        return attachmentChip(icon: "Map", label: title)
    }

    private static func renderLeadingQuoteLine(_ rawLine: String, options: Options) -> [String]? {
        let (line, alignment) = unwrapAlignment(from: rawLine)
        guard line.hasPrefix("[[quote]]"),
              let closeRange = line.range(of: "[[/quote]]") else { return nil }

        let quoteStart = line.index(line.startIndex, offsetBy: 9)
        let quoted = String(line[quoteStart..<closeRange.lowerBound])
        let trailing = String(line[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !trailing.isEmpty else { return nil }

        return [
            "<blockquote><p\(alignmentStyle(alignment))>\(renderInline(quoted, options: options))</p></blockquote>",
            "<p\(alignmentStyle(alignment))>\(renderInline(trailing, options: options))</p>",
        ]
    }

    private static func attachmentChip(icon: String, label: String) -> String {
        "<span class=\"attachment-chip\"><span class=\"attachment-chip-icon\">\(escapeHTML(icon))</span><span class=\"attachment-chip-label\">\(escapeHTML(label))</span></span>"
    }

    private static func alignmentStyle(_ alignment: Alignment?) -> String {
        guard let alignment else { return "" }
        return " style=\"text-align:\(alignment.rawValue)\""
    }

    private static func unwrapAlignment(from line: String) -> (String, Alignment?) {
        let mappings: [(String, Alignment)] = [
            ("[[align:center]]", .center),
            ("[[align:right]]", .right),
            ("[[align:justify]]", .justify),
        ]

        for (prefix, alignment) in mappings where line.hasPrefix(prefix) {
            var content = String(line.dropFirst(prefix.count))
            if content.hasSuffix("[[/align]]") {
                content.removeLast(10)
            }
            return (content, alignment)
        }

        return (line, nil)
    }

    private static func sanitizeColorHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6 || raw.count == 8, raw.allSatisfy(\.isHexDigit) else { return nil }
        return raw
    }

    private static func cssColor(_ hex: String) -> String {
        "#\(hex)"
    }

    private static func cssColor(_ hex: String, alpha: UInt8) -> String {
        let normalized = hex.count == 8 ? String(hex.prefix(6)) : hex
        return "#\(normalized)\(String(format: "%02X", alpha))"
    }

    private static func cardStyleAttributes(_ card: CardData) -> String {
        """
        style="--card-fill-light:\(card.color.lightFillHex);--card-border-light:\(card.color.lightBorderHex);--card-fill-dark:\(card.color.darkFillHex);--card-border-dark:\(card.color.darkBorderHex);width:\(Int(card.width))px;min-height:\(Int(card.height))px"
        """
    }

    private static func tabStyleAttributes(colorHex: String?) -> String {
        guard let raw = colorHex, let sanitized = sanitizeColorHex(raw) else { return "" }
        let fill = cssColor(sanitized, alpha: 0x1A)
        let border = cssColor(sanitized, alpha: 0x33)
        let fg = cssColor(sanitized)
        return " style=\"--tab-accent-fill:\(fill);--tab-accent-border:\(border);--tab-accent-fg:\(fg)\""
    }

    private static func imageMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }
}
