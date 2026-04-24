import Foundation

@MainActor
struct NotePreviewHTMLGenerator {

    static func generate(note: Note) -> String {
        let title = NoteMarkupHTMLRenderer.escapeHTML(note.title.isEmpty ? "Untitled" : note.title)
        let tagsHTML: String
        if note.tags.isEmpty {
            tagsHTML = ""
        } else {
            let pills = note.tags
                .map { "<span class=\"tag\">\(NoteMarkupHTMLRenderer.escapeHTML($0))</span>" }
                .joined()
            tagsHTML = "<div class=\"tags\">\(pills)</div>"
        }
        let bodyHTML = NoteMarkupHTMLRenderer.renderFragment(note.content, context: .quickLook)
        let trimmedBody = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let headerDividerHTML = trimmedBody.isEmpty || trimmedBody.hasPrefix("<hr class=\"note-divider\"")
            ? ""
            : "<div class=\"header-divider\"></div>"

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
            h1 {
              font-size: 22px;
              font-weight: 600;
              margin: 0 0 8px;
              letter-spacing: 0;
            }
            .tags {
              display: flex;
              gap: 6px;
              flex-wrap: wrap;
              margin-bottom: 16px;
            }
            .tag {
              background: var(--tag-bg);
              color: var(--tag-fg);
              border-radius: 999px;
              padding: 2px 10px;
              font-size: 12px;
              font-weight: 500;
            }
            .header-divider {
              height: 1px;
              background: var(--div-clr);
              margin: 16px 0;
            }
            \(NoteMarkupHTMLRenderer.sharedStyles(for: .quickLook))
          </style>
        </head>
        <body>
          <h1>\(title)</h1>
          \(tagsHTML)
          \(headerDividerHTML)
          <div class="note-markup">\(bodyHTML)</div>
        </body>
        </html>
        """
    }
}
