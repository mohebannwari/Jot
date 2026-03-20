# Batch 2: Spotlight Integration + Printing (Cmd+P)

## What We're Building

Two independent macOS system integration features that make Jot a better citizen on the platform.

---

## Feature 1: Spotlight Integration (DES-267)

### Current State
- No CoreSpotlight indexing exists
- No deep linking or `onContinueUserActivity` handling
- No `NSApplicationDelegateAdaptor` in JotApp.swift
- No URL scheme in Info.plist
- `NoteExportService.convertMarkupToPlainText()` already strips all markup tags -- reusable for indexing

### What We're Adding
- Index all notes in macOS Spotlight via `CSSearchableIndex`
- Clicking a Spotlight result opens Jot and navigates to that note
- Locked notes indexed by title only (no content exposed)
- Deleted/archived notes removed from index
- Incremental re-index on app launch (skip unchanged)
- Real-time index updates on create/save/delete

### Architecture

**New file: `Jot/Utils/SpotlightIndexer.swift`**
- `@MainActor` class that wraps `CSSearchableIndex.default()`
- `indexNote(_ note: Note)` -- creates `CSSearchableItem` with attributes
- `deindexNote(id: UUID)` -- removes item from index
- `reindexAll(_ notes: [Note])` -- bulk index, skip unchanged via modifiedAt comparison
- Uses `NoteExportService.convertMarkupToPlainText()` for content extraction
- Domain identifier: `"com.jot.notes"`

**Modified: `Jot/App/JotApp.swift`**
- Add `NSApplicationDelegateAdaptor` for handling `application(_:continue:)` user activity
- Handle `CSSearchableItemActionType` to extract note UUID and navigate

**Modified: `Jot/App/ContentView.swift`**
- Add a `@State var pendingSpotlightNoteID: UUID?` or use a notification
- When the app opens from Spotlight, select and display the target note

**Modified: `Jot/Models/SwiftData/SimpleSwiftDataManager.swift`**
- After `addNote()`, `updateNote()` -- call `SpotlightIndexer.shared.indexNote()`
- After `moveToTrash()`, `deleteNotes()` -- call `SpotlightIndexer.shared.deindexNotes()`
- After `restoreFromTrash()` -- call `SpotlightIndexer.shared.indexNote()` again
- After `archiveNotes()` -- deindex; after `unarchiveNotes()` -- re-index

### Searchable Attributes
```
title          -- note.title (high relevance)
contentDescription -- plain text of note.content (stripped of markup)
keywords       -- note.tags
lastUsedDate   -- note.date (modifiedAt)
thumbnailData  -- nil (no thumbnail for notes)
```

### Deep Link Flow
```
User taps Spotlight result
→ macOS sends NSUserActivity with CSSearchableItemActionType
→ AppDelegate.application(_:continue:) fires
→ Extract note UUID from activity.userInfo
→ Post notification with UUID
→ ContentView receives notification, selects note
```

### Key Files
- New: `Jot/Utils/SpotlightIndexer.swift`
- Modified: `Jot/App/JotApp.swift` -- AppDelegate adaptor
- Modified: `Jot/App/ContentView.swift` -- deep link receiver
- Modified: `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` -- index hooks
- Reuse: `Jot/Utils/NoteExportService.swift` -- `convertMarkupToPlainText()` at line 461

---

## Feature 2: Printing (DES-268)

### Current State
- No print support exists
- Editor is `InlineNSTextView` (custom NSTextView) wrapped in `TodoEditorRepresentable`
- Coordinator stores `private weak var textView: NSTextView?` (line 1151)
- All editor actions use NotificationCenter pattern (8138+ notification names)
- Images/tables/code blocks are overlay views, NOT NSTextAttachments -- won't print natively
- PDF export exists in `NoteExportService` but rebuilds layout manually (doesn't use NSTextView)

### What We're Adding
- Cmd+P opens native macOS print dialog for the current note
- File > Print menu item via `CommandGroup(replacing: .printItem)`
- NSTextView's native rich text printing (formatting, colors, fonts)
- Print-friendly appearance (force light mode for printing)
- Note title and date as print header

### Architecture

**New file: `Jot/App/PrintCommands.swift`**
- `CommandGroup(replacing: .printItem)` with Cmd+P
- Posts `.printCurrentNote` notification

**Modified: `Jot/Views/Components/TodoEditorRepresentable.swift`**
- Add `.printCurrentNote` notification name
- In Coordinator's `configure(with:)`, register observer
- Implement `printNote()` that:
  1. Gets the textView reference
  2. Creates NSPrintInfo with 1-inch margins
  3. Creates NSPrintOperation
  4. Runs the print operation

**Modified: `Jot/App/JotApp.swift`**
- Add `PrintCommands()` to `.commands {}`

### Printing Approach
NSTextView has built-in print support via `NSPrintOperation(view: textView)`. This automatically handles:
- Rich text formatting (bold, italic, underline, strikethrough, colors)
- Custom fonts (Charter, System, Mono)
- Paragraph styles (alignment, indentation, line spacing)
- Multi-page pagination

**Not included in MVP:**
- Images (overlay views, not NSTextAttachments)
- Code block backgrounds (overlay views)
- Tables (overlay views)
- Custom headers/footers (can add later)

### Notification Flow
```
Cmd+P → PrintCommands posts .printCurrentNote
→ Coordinator observes, filters by editorInstanceID
→ Coordinator calls printNote() on its NSTextView
→ Native macOS print dialog appears
```

### Key Files
- New: `Jot/App/PrintCommands.swift`
- Modified: `Jot/Views/Components/TodoEditorRepresentable.swift` -- notification observer + printNote()
- Modified: `Jot/App/JotApp.swift` -- add PrintCommands
- Modified: `Jot/Utils/Extensions.swift` -- new Notification.Name constants

---

## Acceptance Criteria

### Spotlight
- [ ] Notes appear in Spotlight search results (Cmd+Space)
- [ ] Clicking a result opens Jot to the correct note
- [ ] New/edited notes indexed within seconds
- [ ] Deleted notes removed from index
- [ ] Archived notes removed from index
- [ ] Locked notes indexed by title only (no content)
- [ ] Restored notes re-indexed

### Printing
- [ ] Cmd+P opens native macOS print dialog
- [ ] Printed output preserves text formatting (bold, italic, colors, fonts)
- [ ] Multi-page notes paginate correctly
- [ ] File > Print menu item visible in menu bar
- [ ] Print works in both light and dark mode (output is always light)

---

## Out of Scope
- Spotlight: Custom result thumbnails
- Spotlight: Indexing archived notes
- Printing: Images, tables, code blocks in print output (v2)
- Printing: Custom headers/footers with note title/date (v2)
