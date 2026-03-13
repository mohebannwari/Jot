# Smart Code Paste Detection

**Date:** 2026-03-13
**Status:** Approved
**Approach:** Clone the existing URL paste popup pattern (Approach A)

---

## Problem

When a user pastes code into the editor, it arrives as plain text. There's no way to convert it into a code block without manually inserting a code block first and then pasting into it. The app already has a smart paste popup for URLs (offering "Mention" vs "Paste as URL"). Code deserves the same treatment.

## Solution

Add a code detection layer to the paste handler. When code is detected, show a popup offering "Code Block (Language)" or "Plain Text", mirroring the URL paste popup's architecture exactly.

---

## Detection Logic

Two-tier detection runs inside `InlineNSTextView.paste()`, after the existing URL check. URLs always take priority (a GitHub URL is a link, not code).

### Tier 1: Pasteboard Source Detection

Check `NSPasteboard.general` for pasteboard type identifiers that code editors place:
- `com.apple.dt.Xcode.pboard.source-code` (Xcode-specific pasteboard type)
- `public.source-code` UTI

**Note:** `NSPasteboard` does not expose source application bundle IDs. Source detection relies solely on the presence of code-specific pasteboard types listed above.

If any of these types are present, the content is code. Skip heuristic analysis.

### Tier 2: Heuristic Content Analysis

Static method: `isLikelyCode(_ text: String) -> (isCode: Bool, language: String)`

Scoring system:

**Strong signals** (any one sufficient for multi-line, required for single-line):
- Lines starting with: `import `, `func `, `def `, `class `, `struct `, `enum `, `#include`, `package `, `from ... import`, `use `, `module `
- Presence of `=> {`, `-> {`, or lambda/closure syntax
- Lines ending with `{` or `};`

**Medium signals** (need 2+ to trigger):
- Curly braces `{}`
- Semicolons at line ends
- `->` return type arrows
- `//` or `#` line comments
- Assignment patterns: `let x =`, `var x =`, `const x =`, `val x =`
- Indentation: 2+ leading spaces on 50%+ of lines
- Parenthesized function calls: `foo(`, `bar(`

**Negative signals** (reduce score / veto):
- Prose-like lines: 5+ words without operators or braces
- Markdown headers (`# `, `## `)
- Pure natural language (no special characters beyond punctuation)
- Very short text (< 8 characters) with no strong signals

**Single-line threshold:** Require either a Tier 1 match or at least one strong signal. This prevents "let me know about the meeting" from triggering.

### Language Detection

Match keyword clusters to language identifiers from `CodeBlockData.supportedLanguages`. When multiple languages match, use **exclusive keywords** as tiebreakers (listed in priority order):

| Exclusive Keywords | Language | Tiebreaker over |
|----------|----------|-----------------|
| `guard`, `@State`, `@Published`, `import SwiftUI`, `import UIKit` | swift | go (both have `func`) |
| `:=`, `fmt.`, `go func`, `package main` | go | swift (both have `func`) |
| `def`, `elif`, `__init__`, `self.` (at line start) | python | -- |
| `function`, `const`, `=>`, `===`, `console.log`, `require(` | javascript | -- |
| `fn`, `mut`, `impl`, `pub fn`, `::` (outside C++) | rust | -- |
| `public static void`, `System.out`, `@Override` | java | -- |
| `#include`, `std::`, `nullptr`, `int main` | cpp | -- |
| `SELECT`, `FROM`, `WHERE`, `JOIN`, `INSERT INTO` | sql | -- |
| `<div`, `<span`, `<html`, `className=` | html | -- |

**Resolution rule:** Score each language by counting matched keywords. If two languages tie, exclusive keywords win. If still ambiguous, default to `"plaintext"`.

Default to `"plaintext"` when no language is confidently detected.

---

## Paste Flow

### Step 1: Intercept in `InlineNSTextView.paste()`

Location: after existing URL detection (line ~6420)

```
1. Record beforeLocation = selectedRange().location
2. super.paste(sender) — perform normal paste
3. Record afterLocation = selectedRange().location
4. Compute pastedLength = afterLocation - beforeLocation
5. If pastedLength <= 0, return (nothing was inserted)
6. Read the actually-inserted text from textStorage using the computed range
   (DO NOT use the pasteboard string — line-ending normalization may differ)
7. Check isLikelyURL() on inserted text — if true, handle URL popup (existing)
8. If not URL, check isLikelyCode(insertedText)
9. If code detected:
   a. Store pasted range as NSRange(location: beforeLocation, length: pastedLength)
   b. Apply subtle highlight (light gray background tint on the range)
   c. Calculate popup rect from first glyph position of pasted range
   d. Post .codePasteDetected notification with object: [String: Any] dict:
      - "code": String (the inserted text)
      - "range": NSValue(range:) (the pasted range)
      - "rect": NSValue(rect:) (screen position for popup)
      - "language": String (detected language)
```

**Multiline paste safety:** The pasted range is derived from cursor positions before/after `super.paste()`, then the actual inserted text is read back from `textStorage`. This avoids discrepancies from line-ending normalization or attributed string transformations.

### Step 2: Display Popup

Location: `TodoRichTextEditor.swift`, `.onReceive(.codePasteDetected)`

- Extract code, range, rect, language from notification's `object` dict
- Store in SwiftUI `@State`: `codePasteCode`, `codePasteRange`, `codePasteLanguage`
- Calculate menu position: 8px below pasted text, horizontally centered
- Clamp to viewport bounds via `clampedCodePasteMenuPosition()` (menu height: `68 + CommandMenuLayout.outerPadding * 2`, same as URL menu)
- Set SwiftUI state: `showCodePasteMenu = true`
- Set static flag: `InlineNSTextView.isCodePasteMenuShowing = true`

### Step 3: User Chooses

The SwiftUI `CodePasteOptionMenu` posts selection notifications with `object: [String: Any]` carrying the stored code, range, and language from `@State`. Handled in the Coordinator via notification observers.

---

## Notification Architecture

New notifications (alongside existing URL paste set):

| Notification | Purpose | Payload (`object`) |
|-------------|---------|-------------------|
| `.codePasteDetected` | Fired from `paste()` | `["code": String, "range": NSValue, "rect": NSValue, "language": String]` |
| `.codePasteSelectCodeBlock` | User chose "Code Block" | `["code": String, "range": NSValue, "language": String]` |
| `.codePasteSelectPlainText` | User chose "Plain Text" | `["range": NSValue]` |
| `.codePasteDismiss` | Menu dismissed | `["range": NSValue]` (carries range for highlight cleanup) |
| `.codePasteNavigateUp` | Keyboard: Up arrow | `nil` |
| `.codePasteNavigateDown` | Keyboard: Down arrow | `nil` |
| `.codePasteSelectFocused` | Keyboard: Return/Enter | `nil` |

**Key difference from URL system:** `.codePasteDismiss` carries the range in its `object` dict so the Coordinator can reliably call `clearCodePasteHighlight(range:)`. The URL system works around nil-object dismissals by clearing the highlight inside the selection handlers themselves; we do the same for code block/plain text selection but also pass the range on dismiss for the escape/other-key path.

Static flag: `InlineNSTextView.isCodePasteMenuShowing: Bool`

**Mutual exclusivity invariant:** `isCodePasteMenuShowing` and `isURLPasteMenuShowing` must never both be true. This is guaranteed by the detection order in `paste()` (URL check runs first; code check only runs if URL didn't match).

---

## Popup View: `CodePasteOptionMenu`

Modeled after `URLPasteOptionMenu` (TodoRichTextEditor.swift line 543).

### Options

1. **"Code Block (Swift)"** -- code brackets icon, label includes detected language via `CodeBlockData.displayName(for:)`
2. **"Plain Text"** -- text/document icon

### Visual Properties

- Liquid glass background: `.liquidGlass(in: RoundedRectangle(cornerRadius: 28))`
- Shadow: 24pt blur at y+12, 8pt blur at y+4
- Fixed width: 160pt
- Outer padding: 12pt (`CommandMenuLayout.outerPadding`)
- Menu height for clamping: `68 + CommandMenuLayout.outerPadding * 2` (same as URL menu -- 2 rows)
- Hover: capsule background with "HoverBackgroundColor"
- Keyboard focus tracking with color animation (0.12s smooth)
- Icons: 18x18 template images

### Transitions

```swift
.transition(.asymmetric(
    insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
    removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
))
```

### Keyboard Navigation

Mirrors URL paste menu handling in `keyDown()`:
- Up/Down arrows cycle through 2 options
- Return triggers focused option
- Escape dismisses (posts `.codePasteDismiss` with range)
- Any other key dismisses (posts `.codePasteDismiss` with range), then passes through to `super.keyDown()`

---

## Choice Handling

### "Code Block" chosen (`.codePasteSelectCodeBlock`)

1. Extract code, range, language from notification `object` dict
2. Remove highlight from pasted text via `clearCodePasteHighlight(range:)`
3. Select the pasted range in textView
4. Create `CodeBlockData(language: detectedLanguage, code: codeText)`
5. Call existing `makeCodeBlockAttachment(codeBlockData:)`
6. Replace selected range with code block attachment (newline before/after)

### "Plain Text" chosen (`.codePasteSelectPlainText`)

1. Extract range from notification `object` dict
2. Remove highlight via `clearCodePasteHighlight(range:)`
3. Do nothing else -- text is already pasted as plain text from `super.paste()`

### Dismiss (Escape / other key / click outside)

1. Extract range from notification `object` dict
2. Remove highlight via `clearCodePasteHighlight(range:)`
3. Dismiss menu, set `isCodePasteMenuShowing = false`
4. Text stays as plain text -- same as URL dismiss behavior

### `textDidChange` integration

Add `.codePasteDismiss` posting to the existing `textDidChange` handler (line ~3249) alongside the existing `.urlPasteDismiss` post. This ensures the menu dismisses when the user types instead of choosing an option.

---

## `pasteAsPlainText` Override

`pasteAsPlainText(_:)` (Cmd+Shift+V) should **not** trigger code detection. The user is explicitly requesting plain text paste -- showing a "would you like a code block?" popup contradicts that intent.

---

## Files Modified

| File | Changes |
|------|---------|
| `TodoEditorRepresentable.swift` | `isLikelyCode()` static method, `detectCodeLanguage()` static method, `paste()` code detection branch (after URL check, using cursor-delta range), notification constants (7 new), `isCodePasteMenuShowing` static flag, `keyDown()` code paste keyboard handling, Coordinator notification observers for all 4 action notifications, `replaceCodePasteWithCodeBlock(code:range:language:)`, `clearCodePasteHighlight(range:)`, `textDidChange` addition |
| `TodoRichTextEditor.swift` | `CodePasteOptionMenu` view struct, `.onReceive(.codePasteDetected)` handler, `@State showCodePasteMenu`, `@State codePasteCode/Range/Language/MenuPosition`, `clampedCodePasteMenuPosition()`, popup overlay in body alongside URL popup |

---

## Edge Cases

- **Empty paste:** Don't trigger (pastedLength <= 0 guard)
- **URL that looks like code:** URL check runs first, wins
- **Code block overlay has focus:** Paste routes through CodeBlockOverlayView's own text view, not `InlineNSTextView.paste()` -- detection doesn't fire (architecturally moot)
- **Very large pastes (1000+ lines):** Still trigger; code block handles large content
- **Mixed content (code + prose):** Heuristic scores overall content; if code signals dominate, trigger
- **Paste from same app (internal rich text):** Check for app-specific pasteboard types (e.g., Jot's internal attributed string type) before running detection; skip if present
- **Cmd+Shift+V (Paste and Match Style):** Does not trigger code detection (explicit plain text intent)
