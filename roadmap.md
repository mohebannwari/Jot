# Jot -- Feature Roadmap

Gap analysis against Apple Notes (iOS 26 / macOS 26). Ordered for sequential implementation.

Baseline: Jot already matches or exceeds Apple Notes in rich text formatting, tables, lists, checklists, headings, inline links, audio recording, live transcription, audio summaries, photo/video embedding, PDF preview, file attachments, drag-and-drop, folders, tags, pinned notes, sorting, full-text search, Spotlight integration, note locking, AI writing tools, App Intents/Shortcuts, Share Extension, markdown export, and in-note find. Jot-exclusive features include code blocks (20+ languages), callout blocks, tab containers, card sections, highlight/marker, text color, meeting notes with multi-session support, and version history.

---

## Phase 1 -- Quick Wins

### 1. ~~Complete Markdown Import Service~~ DONE

**Status:** Completed
**Changes:** Added setext-style headings, indented code blocks, nested blockquote flattening, soft line break stripping, and bold-italic combination parsing to `Jot/Utils/NoteImportService.swift`.

---

### 2. ~~Web Link Rich Previews~~ DONE (MVP)

**Status:** MVP Completed
**Changes:** Added "Card" as a third option in the URL paste menu (alongside Mention and Plain URL). Selecting "Card" inserts an inline preview card showing title, description, and domain. Metadata is fetched async via `WebMetadataFetcher` and the card updates in place. New serialization tag: `[[linkcard|title|description|url]]`. Full round-trip support (serialize, deserialize, export to MD/HTML/plaintext). MVP card UI in `LinkCardView` -- ready for polish pass.
**Key files:** `TodoEditorRepresentable.swift`, `TodoRichTextEditor.swift`, `WebClipView.swift` (contains `LinkCardView`), `NoteExportService.swift`, `RichTextSerializer.swift`

---

## Phase 2 -- Platform Integration

### 3. ~~Quick Notes (Global Hotkey Capture)~~ DONE

**Status:** Completed
**Changes:** User-configurable global hotkey (default `⌃⇧J`) opens a borderless floating `NSPanel` from any app for plain-text note capture. Carbon `RegisterEventHotKey` is the registration mechanism — works under sandbox without any entitlement, no Accessibility prompt. Saved notes land in an auto-created "Quick Notes" inbox folder, with the folder ID persisted by UUID so renames are honored and deletions trigger transparent recreation. The panel is `.borderless + .nonactivatingPanel + .resizable`, 600×400 default, draggable from anywhere, with a visible Save button that doubles as the `⌘↩` accelerator and a `pendingSave: DispatchWorkItem` guard against double-save and escape-during-save races. Settings → General → Shortcuts has a `HotKeyRecorderView` that surfaces Carbon registration failures inline and reverts the binding so stored chord and active chord can never drift apart.
**Key files:** New: `Jot/Utils/QuickNoteHotKey.swift`, `Jot/Utils/GlobalHotKeyManager.swift`, `Jot/Utils/QuickNoteService.swift`, `Jot/Views/Screens/QuickNotePanel.swift`, `Jot/Views/Components/HotKeyRecorderView.swift`, `JotTests/QuickNoteTests.swift`. Modified: `Jot/Utils/ThemeManager.swift` (new `quickNoteHotKey` published property + `hasFinishedInitialization` flag pattern to fix the `@Published` + `didSet` + init gotcha), `Jot/App/JotApp.swift` (hotkey installation at end of init), `Jot/Views/Components/FloatingSettings.swift` (new Shortcuts section).

---

### 4. Smart Folders

**Status:** Not implemented
**Scope:** Saved filter definitions that auto-populate with matching notes. Filters should support: tags, date range (created/edited), has attachments, has checklists, is pinned, is locked, and keyword match. Smart folders appear in the sidebar alongside regular folders with a distinct icon. Each smart folder stores its filter predicate as JSON.
**Key files:** New `Jot/Models/SmartFolder.swift` (model), new `Jot/Models/SwiftData/SmartFolderEntity.swift`, `Jot/Views/Components/FolderSection.swift` (sidebar integration), `SimpleSwiftDataManager.swift` (query evaluation)
**Effort:** Medium
**Acceptance:** User can create a smart folder with 1+ filter criteria. Notes matching the criteria appear automatically. Adding/removing a tag or attachment from a note updates smart folder membership in real time.

---

## Phase 3 -- Editor Enhancements

### 5. Collapsible Sections (Heading Fold)

**Status:** Not implemented
**Scope:** Allow users to collapse all content beneath a heading (H1/H2/H3) until the next heading of equal or higher level. Add a disclosure triangle (or toggle affordance) to the left of heading lines. Collapsed state should be per-note, per-session (not persisted -- content always serializes fully expanded).
**Key files:** `Jot/Views/Components/TodoEditorRepresentable.swift` (layout manager or text storage manipulation), `Jot/Utils/TextFormattingManager.swift` (heading detection)
**Effort:** Hard -- requires custom `NSLayoutManager` or `NSTextLayoutFragment` work to hide glyph ranges while keeping them in the text storage.
**Acceptance:** Clicking a heading's disclosure triangle hides all content below it until the next same-or-higher-level heading. Re-clicking expands it. Collapsed state does not affect serialization, export, or search.

---

### 6. Map Embedding (Location Pins)

**Status:** Not implemented
**Scope:** Allow embedding a MapKit snapshot inline in a note. User inserts a map pin via the slash command menu or a toolbar action, entering an address or coordinates. The map renders as an inline attachment (similar to image attachments) showing a static MapKit snapshot with a pin. Tapping opens the location in Maps.
**Key files:** New `Jot/Models/MapPinData.swift`, new `Jot/Views/Components/Renderers/MapPreviewRenderer.swift`, `TodoEditorRepresentable.swift` (attachment insertion), `RichTextSerializer.swift` (new `[[map|lat|lon|label]]` tag)
**Effort:** Medium
**Acceptance:** User can insert a map pin by address or coordinates. The map renders inline as a snapshot with a pin marker. Clicking opens Apple Maps. Serialization round-trips correctly.

---

## Phase 4 -- Future Exploration

These features are acknowledged gaps but not planned for immediate implementation. Revisit when the above phases are complete.

### 7. Real-time Collaboration

**Why deferred:** Requires CRDT or CloudKit sharing infrastructure -- significant architectural investment. Single-developer scope makes this impractical short-term.
**Prerequisite:** None (Jot remains fully local by design).

### 8. Document Scanner

**Why deferred:** VisionKit on macOS has limited camera-based scanning support compared to iOS. Could implement as "import scanned PDF" workflow rather than live camera capture.
**Prerequisite:** Phase 1 (markdown import) and Phase 2 (file handling maturity).

### 9. Widgets (WidgetKit)

**Why deferred:** Read-only WidgetKit target. Requires shared App Group data access (already in place) but lower priority than editor features.
**Prerequisite:** None blocking.

### 10. Siri Integration

**Why deferred:** App Intents already exist (create, open, search, append). Siri donation and voice activation are incremental additions but low user demand for a macOS-primary app.
**Prerequisite:** None blocking.

---

## Excluded (Not Planned)

| Feature                           | Reason                                       |
| --------------------------------- | -------------------------------------------- |
| iCloud Sync                       | Jot is fully local by design                 |
| Math Notes                        | Out of scope -- not aligned with Jot's focus |
| Drawing / Handwriting (PencilKit) | macOS-primary app, iPad-centric feature      |
| Handwriting Search                | No drawing layer to search                   |
| Apple Watch Support               | macOS-only app                               |
| Phone Call Recording              | iOS-only feature                             |

---

## Implementation Sequence

```
Phase 1 (Quick Wins)
  1. Complete Markdown Import -----> small effort
  2. Web Link Rich Previews ------> medium effort

Phase 2 (Platform Integration)
  3. Quick Notes -----------------> medium effort
  4. Smart Folders ---------------> medium effort

Phase 3 (Editor Enhancements)
  5. Collapsible Sections --------> hard effort
  6. Map Embedding ---------------> medium effort

Phase 4 (Future Exploration)
  7. Real-time Collaboration
  8. Document Scanner
  9. Widgets
  10. Siri Integration
```
