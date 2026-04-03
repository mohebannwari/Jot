# Mention Quick Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking "Quick Look" on a `@mention` pill opens the native macOS QLPreviewPanel showing the mentioned note's content as styled HTML — identical UX to link Quick Look.

**Architecture:** `handleAttachmentHover()` already fires for `NotelinkAttachment` (the hover tooltip shows up). The only missing piece is that `resolveQuickLookURL()` returns `nil` for notelinks. We add: (1) a `fetchNote: ((UUID) -> Note?)` closure threaded from `NoteDetailView` → `TodoRichTextEditor` → `TodoEditorRepresentable` → `Coordinator`; (2) a notelink case in `resolveQuickLookURL()` that calls a new `generateNotePreviewHTML(for:)` helper; (3) a standalone `NotePreviewHTMLGenerator` struct that converts serialized note markup to a self-contained HTML file. The HTML file is written to `/tmp` and handed to `QLPreviewPanel` exactly like `.webloc` files for web clips.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, QLPreviewPanel, NSTextAttributedString

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Jot/Utils/NotePreviewHTMLGenerator.swift` | **Create** | Pure markup→HTML converter; all testable logic lives here |
| `Jot/Views/Components/TodoEditorRepresentable.swift` | **Modify** | Add `fetchNote` to struct + Coordinator; add notelink case in `resolveQuickLookURL`; add `generateNotePreviewHTML` |
| `Jot/Views/Components/TodoRichTextEditor.swift` | **Modify** | Thread `fetchNote` parameter down to `TodoEditorRepresentable` |
| `Jot/Views/Screens/NoteDetailView.swift` | **Modify** | Provide `fetchNote` closure closing over `notesManager.notes` |
| `JotTests/NoteQuickLookTests.swift` | **Create** | Unit tests for `NotePreviewHTMLGenerator` |

---

## Task 1: Create `NotePreviewHTMLGenerator` with failing tests

**Files:**
- Create: `JotTests/NoteQuickLookTests.swift`
- Create: `Jot/Utils/NotePreviewHTMLGenerator.swift` (stub only in this task)

- [ ] **Step 1: Create the stub file so the test target can reference it**

Create `Jot/Utils/NotePreviewHTMLGenerator.swift`:

```swift
// NotePreviewHTMLGenerator.swift
// Jot

import Foundation

struct NotePreviewHTMLGenerator {
    static func generate(note: Note) -> String { "" }
    static func parseContent(_ content: String) -> String { "" }
    static func parseLine(_ line: String) -> String { "" }
    static func processInline(_ text: String) -> String { "" }
    static func escapeHTML(_ text: String) -> String { "" }
}
```

- [ ] **Step 2: Write the failing tests**

Create `JotTests/NoteQuickLookTests.swift`:

```swift
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
        XCTAssertTrue(result.contains("☑"), "Expected check symbol, got: \(result)")
        XCTAssertTrue(result.contains("Buy groceries"), "Expected text, got: \(result)")
    }

    func testLine_todoPending() {
        let result = NotePreviewHTMLGenerator.parseLine("[ ] Buy groceries")
        XCTAssertFalse(result.contains("todo-done"), "Should not have strikethrough, got: \(result)")
        XCTAssertTrue(result.contains("☐"), "Expected empty checkbox, got: \(result)")
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
        let note = Note(
            title: "My Note",
            content: "Some content",
            date: Date(),
            tags: []
        )
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("<h1>My Note</h1>"), "Expected h1 title, got excerpt: \(html.prefix(500))")
    }

    func testGenerate_containsTags() {
        let note = Note(
            title: "Tagged",
            content: "",
            date: Date(),
            tags: ["work", "urgent"]
        )
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("work"), "Expected tag 'work'")
        XCTAssertTrue(html.contains("urgent"), "Expected tag 'urgent'")
    }

    func testGenerate_escapesTitle() {
        let note = Note(
            title: "<Script>",
            content: "",
            date: Date(),
            tags: []
        )
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertFalse(html.contains("<Script>"), "Raw unescaped tag should not appear")
        XCTAssertTrue(html.contains("&lt;Script&gt;"), "Expected escaped title")
    }

    func testGenerate_rendersBody() {
        let note = Note(
            title: "Test",
            content: "[[b]]Bold[[/b]] and normal",
            date: Date(),
            tags: []
        )
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("<strong>Bold</strong>"), "Expected bold rendering in body")
    }

    func testGenerate_emptyTitleFallback() {
        let note = Note(title: "", content: "", date: Date(), tags: [])
        let html = NotePreviewHTMLGenerator.generate(note: note)
        XCTAssertTrue(html.contains("Untitled"), "Empty title should fall back to 'Untitled'")
    }
}
```

- [ ] **Step 3: Run the tests — verify they fail**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/NoteQuickLookTests test 2>&1 | tail -30
```

Expected: multiple test failures (stub returns empty strings).

- [ ] **Step 4: Commit the stub and tests**

```bash
git add Jot/Utils/NotePreviewHTMLGenerator.swift JotTests/NoteQuickLookTests.swift
git commit -m "test: add NoteQuickLookTests with failing cases for HTML generator"
```

---

## Task 2: Implement `NotePreviewHTMLGenerator`

**Files:**
- Modify: `Jot/Utils/NotePreviewHTMLGenerator.swift`

- [ ] **Step 1: Replace stub with full implementation**

Replace the entire contents of `Jot/Utils/NotePreviewHTMLGenerator.swift`:

```swift
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
        // Heading blocks — wrap entire line
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
```

- [ ] **Step 2: Run the tests — verify they pass**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/NoteQuickLookTests test 2>&1 | tail -30
```

Expected: all tests `PASS`.

- [ ] **Step 3: Commit**

```bash
git add Jot/Utils/NotePreviewHTMLGenerator.swift
git commit -m "feat: implement NotePreviewHTMLGenerator — rich text markup to styled HTML"
```

---

## Task 3: Add `fetchNote` closure to `TodoEditorRepresentable` and `Coordinator`

**Files:**
- Modify: `Jot/Views/Components/TodoEditorRepresentable.swift`

The `Coordinator` class stores `var onNavigateToNote: ((UUID) -> Void)?`. Add `var fetchNote: ((UUID) -> Note?)?` alongside it, and mirror the same pattern in the `TodoEditorRepresentable` struct + `updateNSView`.

- [ ] **Step 1: Add `fetchNote` to the `Coordinator` class**

In `TodoEditorRepresentable.swift`, find the Coordinator class declaration. It contains `var onResizeEnded: ((CGFloat) -> Void)?` (near line 1003) and `var onNavigateToNote: ((UUID) -> Void)?`. Add `fetchNote` after `onNavigateToNote`:

```swift
// Find this line in the Coordinator class:
var onNavigateToNote: ((UUID) -> Void)?
// Add immediately after:
var fetchNote: ((UUID) -> Note?)?
```

- [ ] **Step 2: Add `fetchNote` to the `TodoEditorRepresentable` struct**

In the `TodoEditorRepresentable` struct declaration, find (line ~1299):

```swift
var onNavigateToNote: ((UUID) -> Void)?
```

Add immediately after:

```swift
var fetchNote: ((UUID) -> Note?)?
```

- [ ] **Step 3: Sync `fetchNote` to the Coordinator in `updateNSView`**

In `updateNSView(context:)`, find (line ~1424):

```swift
// Sync navigate callback
context.coordinator.onNavigateToNote = onNavigateToNote
```

Add immediately after:

```swift
context.coordinator.fetchNote = fetchNote
```

- [ ] **Step 4: Build — verify no compile errors**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add Jot/Views/Components/TodoEditorRepresentable.swift
git commit -m "feat: add fetchNote closure to TodoEditorRepresentable coordinator"
```

---

## Task 4: Add notelink case and `generateNotePreviewHTML` to `resolveQuickLookURL`

**Files:**
- Modify: `Jot/Views/Components/TodoEditorRepresentable.swift`

- [ ] **Step 1: Add `generateNotePreviewHTML(for:)` helper to the Coordinator**

In `TodoEditorRepresentable.swift`, find `resolveQuickLookURL(at:in:)` (line ~3403). Immediately before it (so it appears in source before the caller), add this private method inside the same class/extension:

```swift
/// Serializes the given note to a temp HTML file and returns its URL for QLPreviewPanel.
@MainActor
private func generateNotePreviewHTML(for note: Note) -> URL? {
    let html = NotePreviewHTMLGenerator.generate(note: note)
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("jot_note_preview_\(note.id.uuidString).html")
    do {
        try html.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    } catch {
        return nil
    }
}
```

- [ ] **Step 2: Insert notelink case into `resolveQuickLookURL`**

In `resolveQuickLookURL(at:in:)`, find the line that begins case 3 (web clip):

```swift
// 3. Web clip URL
if attrs[.webClipTitle] != nil,
```

Insert the following block **immediately before** it:

```swift
// Note mention — serialize note content to a temp HTML file
if let idStr = attrs[.notelinkID] as? String,
   let noteID = UUID(uuidString: idStr),
   let note = fetchNote?(noteID) {
    return generateNotePreviewHTML(for: note)
}
```

- [ ] **Step 3: Build — verify no compile errors**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add Jot/Views/Components/TodoEditorRepresentable.swift
git commit -m "feat: resolve notelink Quick Look URL via NotePreviewHTMLGenerator"
```

---

## Task 5: Thread `fetchNote` through `TodoRichTextEditor` and `NoteDetailView`

**Files:**
- Modify: `Jot/Views/Components/TodoRichTextEditor.swift`
- Modify: `Jot/Views/Screens/NoteDetailView.swift`

- [ ] **Step 1: Add `fetchNote` parameter to `TodoRichTextEditor`**

In `TodoRichTextEditor.swift`, find the struct declaration and stored property `onNavigateToNote` (line ~20):

```swift
var onNavigateToNote: ((UUID) -> Void)?
```

Add immediately after:

```swift
var fetchNote: ((UUID) -> Note?)?
```

- [ ] **Step 2: Add `fetchNote` to `TodoRichTextEditor.init`**

Find the `init(` block (line ~23). It currently ends with:

```swift
onNavigateToNote: ((UUID) -> Void)? = nil
```

Add a new parameter after it:

```swift
fetchNote: ((UUID) -> Note?)? = nil
```

And inside the `init` body, add the assignment:

```swift
self.fetchNote = fetchNote
```

- [ ] **Step 3: Pass `fetchNote` into `TodoEditorRepresentable`**

Find where `TodoEditorRepresentable` is initialized inside `TodoRichTextEditor` (line ~123):

```swift
TodoEditorRepresentable(
    text: $text,
    colorScheme: colorScheme,
    focusRequestID: focusRequestID,
    editorInstanceID: editorInstanceID,
    onNavigateToNote: onNavigateToNote
)
```

Add `fetchNote` as a new argument:

```swift
TodoEditorRepresentable(
    text: $text,
    colorScheme: colorScheme,
    focusRequestID: focusRequestID,
    editorInstanceID: editorInstanceID,
    onNavigateToNote: onNavigateToNote,
    fetchNote: fetchNote
)
```

- [ ] **Step 4: Provide `fetchNote` closure in `NoteDetailView`**

In `NoteDetailView.swift`, find the `TodoRichTextEditor` initializer (line ~396):

```swift
TodoRichTextEditor(
    text: $editedContent,
    focusRequestID: localEditorFocusID ?? focusRequestID,
    editorInstanceID: editorInstanceID,
    onToolbarAction: handleEditToolAction,
    onCommandMenuSelection: { performAuxiliaryToolAction($0) },
    availableNotes: availableNotes,
    onNavigateToNote: onNavigateToNote
)
```

Add `fetchNote` as the final argument:

```swift
TodoRichTextEditor(
    text: $editedContent,
    focusRequestID: localEditorFocusID ?? focusRequestID,
    editorInstanceID: editorInstanceID,
    onToolbarAction: handleEditToolAction,
    onCommandMenuSelection: { performAuxiliaryToolAction($0) },
    availableNotes: availableNotes,
    onNavigateToNote: onNavigateToNote,
    fetchNote: { uuid in notesManager.notes.first(where: { $0.id == uuid }) }
)
```

`notesManager` is the `@EnvironmentObject var notesManager: SimpleSwiftDataManager` already present on `NoteDetailView`. The closure captures it by reference, so it always reads the latest `notes` array at call time.

- [ ] **Step 5: Build — verify no compile errors**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 6: Run full test suite**

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: all tests pass including `NoteQuickLookTests`.

- [ ] **Step 7: Commit**

```bash
git add Jot/Views/Components/TodoRichTextEditor.swift \
        Jot/Views/Screens/NoteDetailView.swift
git commit -m "feat: wire fetchNote closure — mention Quick Look end-to-end"
```
