// NotePreviewHTMLGenerator.swift
// Jot
//
// Converts a Note's serialized rich text markup into a self-contained HTML file
// for display in macOS QLPreviewPanel. Mirrors Jot's design tokens via CSS
// prefers-color-scheme so it adapts to system dark/light mode automatically.

import Foundation

struct NotePreviewHTMLGenerator {

    // MARK: - Public API

    /// Returns a complete HTML document string for the given note.
    static func generate(note: Note) -> String {
        let title = escapeHTML(note.title.isEmpty ? "Untitled" : note.title)
        let tagsHTML: String
        if note.tags.isEmpty {
            tagsHTML = ""
        } else {
            let pills = note.tags.map { "<span class=\"tag\">\(escapeHTML($0))</span>" }.joined()
            tagsHTML = "<div class=\"tags\">\(pills)</div>"
        }
        let bodyHTML = parseContent(note.content)

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              --bg: #ffffff;
              --fg: #1a1a1a;
              --fg2: rgba(26,26,26,0.7);
              --tag-bg: rgba(96,141,250,0.24);
              --tag-fg: #1a1a1a;
              --attach-bg: #f5f4f4;
              --div-clr: rgba(0,0,0,0.1);
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #1c1918;
                --fg: #ffffff;
                --fg2: rgba(255,255,255,0.7);
                --tag-bg: rgba(96,141,250,0.16);
                --tag-fg: #608dfa;
                --attach-bg: #292524;
                --div-clr: rgba(255,255,255,0.1);
              }
            }
            * { box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
              background: var(--bg);
              color: var(--fg);
              padding: 28px 36px;
              max-width: 700px;
              margin: 0 auto;
              font-size: 15px;
              line-height: 1.65;
            }
            h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; letter-spacing: -0.3px; }
            h2 { font-size: 18px; font-weight: 600; margin: 22px 0 6px; letter-spacing: -0.2px; }
            h3 { font-size: 16px; font-weight: 600; margin: 18px 0 5px; }
            h4 { font-size: 14px; font-weight: 600; margin: 14px 0 4px; }
            p  { margin: 0 0 4px; }
            .tags { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 16px; }
            .tag {
              background: var(--tag-bg);
              color: var(--tag-fg);
              border-radius: 999px;
              padding: 2px 10px;
              font-size: 12px;
              font-weight: 500;
            }
            .divider { height: 1px; background: var(--div-clr); margin: 16px 0; }
            .attachment {
              background: var(--attach-bg);
              border-radius: 8px;
              padding: 6px 12px;
              font-size: 13px;
              color: var(--fg2);
              margin: 6px 0;
              display: inline-block;
            }
            .todo-done { text-decoration: line-through; opacity: 0.55; }
            a { color: #608dfa; text-decoration: none; }
            a:hover { text-decoration: underline; }
          </style>
        </head>
        <body>
          <h1>\(title)</h1>
          \(tagsHTML)
          <div class="divider"></div>
          \(bodyHTML)
        </body>
        </html>
        """
    }

    // MARK: - Content Parser

    /// Converts the full serialized note content (multi-line markup) to an HTML fragment.
    static func parseContent(_ content: String) -> String {
        guard !content.isEmpty else { return "" }
        return content
            .components(separatedBy: "\n")
            .map { parseLine($0) }
            .joined(separator: "\n")
    }

    /// Converts one line of serialized markup to its HTML equivalent.
    static func parseLine(_ line: String) -> String {
        // Heading blocks — whole-line wrappers
        if line.hasPrefix("[[h1]]") && line.hasSuffix("[[/h1]]") {
            return "<h2>\(processInline(String(line.dropFirst(6).dropLast(7))))</h2>"
        }
        if line.hasPrefix("[[h2]]") && line.hasSuffix("[[/h2]]") {
            return "<h3>\(processInline(String(line.dropFirst(6).dropLast(7))))</h3>"
        }
        if line.hasPrefix("[[h3]]") && line.hasSuffix("[[/h3]]") {
            return "<h4>\(processInline(String(line.dropFirst(6).dropLast(7))))</h4>"
        }

        // Todo items
        if line.hasPrefix("[x] ") {
            return "<p class=\"todo-done\">&#9745; \(processInline(String(line.dropFirst(4))))</p>"
        }
        if line.hasPrefix("[ ] ") {
            return "<p>&#9744; \(processInline(String(line.dropFirst(4))))</p>"
        }

        // Attachment tokens — render as labelled placeholder blocks
        if line.hasPrefix("[[image|") {
            return "<div class=\"attachment\">&#128247; Image</div>"
        }
        if line.hasPrefix(MapBlockData.markupPrefix) {
            let title = MapBlockData.deserialize(from: line)?.displayTitle ?? "Map"
            return "<div class=\"attachment\">&#128506; \(escapeHTML(title))</div>"
        }
        if line.hasPrefix("[[file|") {
            // Format: [[file|type|storedName|originalName|viewMode]]
            let inner = String(line.dropFirst(7).dropLast(2))
            let parts = inner.components(separatedBy: "|")
            let name = parts.count >= 3 ? escapeHTML(parts[2]) : "File"
            return "<div class=\"attachment\">&#128196; \(name)</div>"
        }
        if line.hasPrefix("[[webclip|") {
            let inner = String(line.dropFirst(10).dropLast(2))
            let title = escapeHTML(inner.components(separatedBy: "|").first ?? "Web Clip")
            return "<div class=\"attachment\">&#128279; \(title)</div>"
        }

        // Alignment wrapper — strip wrapper, process inner content
        if line.hasPrefix("[[align:"), let closeRange = line.range(of: "]]") {
            let afterOpen = String(line[closeRange.upperBound...])
            let inner = afterOpen.hasSuffix("[[/align]]")
                ? String(afterOpen.dropLast(10))
                : afterOpen
            return "<p>\(processInline(inner))</p>"
        }

        // Empty line
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return "<br>"
        }

        // Default: paragraph
        return "<p>\(processInline(line))</p>"
    }

    /// Converts inline markup tokens within a single line to HTML equivalents.
    static func processInline(_ text: String) -> String {
        var result = text

        // Inline formatting pairs
        result = result.replacingOccurrences(of: "[[b]]",  with: "<strong>")
        result = result.replacingOccurrences(of: "[[/b]]", with: "</strong>")
        result = result.replacingOccurrences(of: "[[i]]",  with: "<em>")
        result = result.replacingOccurrences(of: "[[/i]]", with: "</em>")
        result = result.replacingOccurrences(of: "[[u]]",  with: "<u>")
        result = result.replacingOccurrences(of: "[[/u]]", with: "</u>")
        result = result.replacingOccurrences(of: "[[s]]",  with: "<s>")
        result = result.replacingOccurrences(of: "[[/s]]", with: "</s>")
        result = result.replacingOccurrences(of: "[[/color]]", with: "</span>")

        // [[color|#hex]]…[[/color]] → <span style="color:#hex">
        if let colorRegex = try? NSRegularExpression(pattern: #"\[\[color\|([^\]]+)\]\]"#) {
            result = colorRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "<span style=\"color:$1\">"
            )
        }

        // [[link|type|url|label]] → <a href="url">label</a>
        if let linkRegex = try? NSRegularExpression(pattern: #"\[\[link\|[^|]*\|([^|]*)\|([^\]]+)\]\]"#) {
            result = linkRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "<a href=\"$1\">$2</a>"
            )
        }

        return result
    }

    /// Escapes the four characters that are unsafe in HTML text content and attribute values.
    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
