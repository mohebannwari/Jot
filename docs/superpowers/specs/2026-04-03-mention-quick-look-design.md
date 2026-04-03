# Quick Look for Note Mentions — Design Spec

**Date:** 2026-04-03  
**Status:** Approved

---

## Problem

Hovering a `@mention` pill in the editor already shows the "Quick Look" tooltip (same as links), but clicking it does nothing. `resolveQuickLookURL()` has no case for notelinks and returns `nil`, so `QLPreviewPanel` never opens.

---

## Solution

Add a notelink case to `resolveQuickLookURL()` that:
1. Looks up the `NoteEntity` by UUID
2. Serializes its content to a styled HTML temp file
3. Returns that URL to `QLPreviewPanel` — the same panel used for web clips

No new UI, no new panel, no new trigger logic. Identical UX to link/web clip Quick Look.

---

## Architecture

### 1. Note fetch callback — `TodoEditorRepresentable`

Add `var fetchNote: ((UUID) -> NoteEntity?)?` following the existing `onNavigateToNote` pattern:

- Declared on `TodoEditorRepresentable` struct
- Synced to `Coordinator` in `updateNSView()` (line ~1424)
- Stored on `Coordinator` as `var fetchNote: ((UUID) -> NoteEntity?)?`
- Provided by `NoteDetailView` (which has access to `SimpleSwiftDataManager`)

### 2. `resolveQuickLookURL()` — new notelink case

Insert before the existing web clip case (~line 3421):

```swift
// 0. Note mention link
if let notelinkIDStr = attrs[.notelinkID] as? String,
   let noteID = UUID(uuidString: notelinkIDStr),
   let note = fetchNote?(noteID) {
    return generateNotePreviewHTML(for: note)
}
```

### 3. `generateNotePreviewHTML(for:)` — HTML serializer

New private method on `Coordinator`. Converts the note's serialized rich text to a self-contained HTML file, written to `/tmp/jot_note_preview_<noteID>.html`. Returns the file URL.

**HTML output structure:**
- `<meta charset="utf-8">` + `prefers-color-scheme` CSS for auto dark/light
- SF Pro font via `-apple-system` stack
- Note title as `<h1>`
- Tags as colored pills
- Body parsed from rich text markup (see serialization section below)
- No JavaScript, no external resources

**Rich text → HTML mapping:**

| Markup | HTML |
|--------|------|
| `[[b]]...[[/b]]` | `<strong>` |
| `[[i]]...[[/i]]` | `<em>` |
| `[[u]]...[[/u]]` | `<u>` |
| `[[s]]...[[/s]]` | `<s>` |
| `[[h1]]...[[/h1]]` | `<h2>` (h1 reserved for note title) |
| `[[h2]]...[[/h2]]` | `<h3>` |
| `[[h3]]...[[/h3]]` | `<h4>` |
| `[[color\|hex]]...[[/color]]` | `<span style="color:#hex">` |
| `[x]` | `☑` (with strikethrough on line) |
| `[ ]` | `☐` |
| `[[image\|...\|filename]]` | `<div class="attachment">📎 Image</div>` |
| `[[file\|...\|...\|original\|...]]` | `<div class="attachment">📄 filename</div>` |
| `[[webclip\|title\|...\|url]]` | `<div class="attachment">🔗 title</div>` |
| `[[link\|...\|url\|label]]` | `<a href="url">label</a>` |
| Line break | `<br>` |

**CSS themes (via `prefers-color-scheme`):**

| Property | Light | Dark |
|----------|-------|------|
| `background` | `#ffffff` | `#1c1918` |
| `color` | `#1a1a1a` | `#ffffff` |
| `h1/h2/h3` | `#1a1a1a` | `#ffffff` |
| Tag pills | `#608DFA59` / `#608DFA` | `#608DFA40` / `#608dfa` |
| Attachment block bg | `#f5f4f4` | `#292524` |

### 4. Temp file management

- Path: `/tmp/jot_note_preview_<noteID.uuidString>.html`
- Overwrite on each open (no cleanup needed — `/tmp` is ephemeral)
- Write synchronously (HTML generation is fast; no async needed)

---

## Files to Change

| File | Change |
|------|--------|
| `TodoEditorRepresentable.swift` | Add `fetchNote` callback, add notelink case in `resolveQuickLookURL()`, add `generateNotePreviewHTML()` |
| `TodoRichTextEditor.swift` | Pass `fetchNote` closure into `TodoEditorRepresentable` |
| `NoteDetailView.swift` | Provide `fetchNote` closure (lookup via `SimpleSwiftDataManager`) |

---

## Out of Scope

- Editing the note from the Quick Look preview
- Rendering embedded images (they appear as placeholder indicators)
- Caching HTML output (temp file overwrite is fine)
- Scroll position memory
