# Quick Notes (Global Hotkey Capture) — Design Spec

**Date:** 2026-04-09
**Status:** Approved
**Roadmap:** Phase 2, Feature 3 (`roadmap.md`)

---

## Problem

Jot has no way to capture a thought without bringing the main window forward, opening the sidebar, clicking New Note, and starting to type. Quick Notes in Apple Notes solves this with a system-wide hotkey that spawns a floating panel from any app. Jot should match.

---

## Solution

A single user-configurable global hotkey (default `⌃⌥⌘N`) that spawns a minimal plain-text floating panel (title + body) from any app. Saved notes land in an auto-created "Quick Notes" inbox folder. The panel does not steal focus from the frontmost app — the user returns to whatever they were doing the moment they save or cancel.

**Plain text only** — no rich formatting, no attachments, no checklists. Users who want formatting open the note in the main Jot window afterwards.

**Carbon `RegisterEventHotKey`** for hotkey registration — works under the macOS sandbox without any entitlement, accessibility permission, or TCC prompt. Rejected: `NSEvent.addGlobalMonitorForEvents` (requires Accessibility), third-party libraries (adds dependency for ~150 lines of native code).

---

## Architecture

### 1. Hotkey subsystem

**`QuickNoteHotKey`** — `Codable` value type stored in UserDefaults as JSON.

```swift
struct QuickNoteHotKey: Codable, Equatable {
    var keyCode: UInt32    // Carbon virtual key code
    var modifiers: UInt32  // Carbon modifier bitmask
    var displayString: String { /* "⌃⌥⌘N" */ }
}
```

UserDefaults key: `"jot.quickNote.hotkey"`. Default on first launch: `⌃⌥⌘N` (`keyCode: 0x2D (kVK_ANSI_N)`, `modifiers: cmdKey | optionKey | controlKey`).

**`GlobalHotKeyManager`** — singleton wrapping one `EventHotKeyRef` and one `EventHandlerRef`.

```swift
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    var onFire: (() -> Void)?

    func install(_ hotKey: QuickNoteHotKey)
    func uninstall()
    func replace(with newHotKey: QuickNoteHotKey)
}
```

C callback dispatches to `onFire` on the main queue via `DispatchQueue.main.async`. No ID registry, no map lookups — exactly one global hotkey in the whole app.

**Cocoa ↔ Carbon modifier translation** — pure functions, ~8 lines each direction. Cocoa `NSEvent.ModifierFlags` → Carbon bitmask for storage and registration. Carbon → Unicode glyph string (`⌃⌥⌘N`) for display. Fully unit-testable.

### 2. Panel subsystem

**`QuickNotePanelWindow`** — `NSPanel` subclass.

```swift
final class QuickNotePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- **Style mask:** `[.titled, .closable, .nonactivatingPanel, .fullSizeContentView]`
- `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `isMovableByWindowBackground = true`
- **Window level:** `.floating`
- **Collection behavior:** `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`
- **Initial size:** `480 × 320` pt, centered on the screen containing the mouse cursor
- **Frame autosave:** `"QuickNotePanel"` — restores last position on subsequent shows

**`QuickNoteWindowController`** — singleton. Lazy-instantiates the panel on first `showPanel()`, retains for the app lifetime.

```swift
func showPanel() {
    previousApp = NSWorkspace.shared.frontmostApplication
    if panel == nil { panel = makePanel() }
    panel?.makeKeyAndOrderFront(nil)
}

func dismissPanel(saved: Bool) {
    panel?.orderOut(nil)
    previousApp?.activate()
}
```

**`QuickNotePanelView`** — SwiftUI root, hosted via `NSHostingView`.

```
VStack(spacing: 0)
  ├─ TitleField    (TextField, large font, auto-focused via @FocusState)
  ├─ BodyEditor    (TextEditor, body font, grows to fill)
  └─ Footer        ("⌘↩ to save · esc to cancel")
```

Wrapped in a `RoundedRectangle` with `.glassEffect(in:)` and Jot's `MainColor` tint. Liquid Glass applied on the inner container per Jot's rules (no glass on chrome).

**Keyboard handling** via `.onKeyPress`:

- `⌘↩` → save
- `escape` → cancel (silent discard)

**Save flow:**

1. `QuickNoteService.save(title:body:)` called
2. Footer swaps to "✓ Saved" for 400ms
3. Panel fades out (`animator().alphaValue = 0`, 200ms)
4. `dismissPanel(saved: true)` → focus restored to previous app
5. Panel state reset (empty fields) for next show

**Cancel flow:** same as save but no service call, no checkmark.

### 3. Storage — Quick Notes inbox folder

**`QuickNoteService`** — single save path.

```swift
final class QuickNoteService {
    static let shared = QuickNoteService(manager: .shared, defaults: .standard)

    @discardableResult
    func save(title: String, body: String) -> Note {
        let folderID = resolveOrCreateQuickNotesFolder()
        let effectiveTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? firstLine(of: body) ?? "Quick Note"
            : title
        return manager.addNote(title: effectiveTitle, content: body, folderID: folderID)
    }
}
```

**Folder resolution:**

1. Read `quickNotesFolderID` from ThemeManager.
2. Valid UUID → real folder? Use it.
3. Nil / stale → create folder named "Quick Notes", persist its ID, use it.

The folder is a regular Jot folder — user can rename, recolor, pin, delete. Name is only used at creation time; ID is the source of truth.

**Title fallback:** empty title → derive from first non-empty line of body (truncated to ~60 chars). Empty body too → literal `"Quick Note"`.

### 4. Settings integration

**`HotKeyRecorderView`** — SwiftUI button for the Settings UI.

- Label: current chord (`⌃⌥⌘N`) or placeholder ("Click to record")
- On tap → recording state
- Local `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` captures next chord
- Validates: must have at least one modifier (pure letter keys rejected)
- Escape during recording cancels without changing anything
- On capture: write new value via `ThemeManager`, call `GlobalHotKeyManager.replace(with:)`
- `[Clear]` button unbinds entirely

**Settings row** (location TBD — existing Keyboard/Shortcuts tab, to verify before implementation):

```
Quick Notes
Open a floating note panel from any app
Shortcut:  [ ⌃⌥⌘N ]  [Clear]
```

### 5. App wiring

`JotApp.init` at the end of the existing init:

```swift
let hotKey = themeManager.quickNoteHotKey ?? .default
GlobalHotKeyManager.shared.onFire = { QuickNoteWindowController.shared.showPanel() }
GlobalHotKeyManager.shared.install(hotKey)
```

Hotkey is live before `ContentView` even appears.

---

## Runtime ownership tree

```
JotApp (@main)
├── GlobalHotKeyManager (singleton, installed at launch)
│   └── on fire → QuickNoteWindowController.showPanel()
├── QuickNoteWindowController (singleton, lazy panel creation)
│   └── owns QuickNotePanelWindow (NSPanel subclass)
│       └── contentView = NSHostingView<QuickNotePanelView>
└── SimpleSwiftDataManager (existing, shared instance reused)
```

---

## Files to Change

### New

| File                                            | Responsibility                                    |
| ----------------------------------------------- | ------------------------------------------------- |
| `Jot/Utils/GlobalHotKeyManager.swift`           | Carbon wrapper (~150 lines)                       |
| `Jot/Utils/QuickNoteHotKey.swift`               | Value type, codec, display formatter              |
| `Jot/Utils/QuickNoteService.swift`              | Folder resolution + save path                     |
| `Jot/Views/Screens/QuickNotePanel.swift`        | NSPanel subclass, window controller, SwiftUI view |
| `Jot/Views/Components/HotKeyRecorderView.swift` | Settings chord recorder                           |
| `JotTests/QuickNoteTests.swift`                 | Unit tests                                        |

### Modified

| File                                                              | Change                                                              |
| ----------------------------------------------------------------- | ------------------------------------------------------------------- |
| `Jot/App/JotApp.swift`                                            | Register hotkey at launch, wire callback to window controller       |
| `Jot/Utils/ThemeManager.swift`                                    | Add `quickNoteHotKey` and `quickNotesFolderID` persisted properties |
| `Jot/Views/Screens/SettingsView.swift` (or Keyboard settings tab) | Add Quick Notes row with `HotKeyRecorderView`                       |

### Explicitly NOT touched

- `TodoEditorRepresentable.swift`, `TodoRichTextEditor.swift`, `ContentView.swift`, `NoteDetailView.swift`
- Any existing "FloatingPanel" (`MeetingNotesFloatingPanel` etc.) — those are SwiftUI overlays, not real windows
- `NoteEntity` / SwiftData schema — `addNote` already accepts everything needed

---

## Edge cases

| #   | Situation                                       | Handling                                                                                                                                                                                                                                               |
| --- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Hotkey already owned at install time            | `RegisterEventHotKey` returns non-zero `OSStatus`. Log, leave previous installed. On default-hotkey failure at first launch, surface a one-time banner in main window: _"Quick Notes hotkey (⌃⌥⌘N) couldn't be registered. Pick another in Settings."_ |
| 2   | Hotkey fires while panel is already visible     | `showPanel()` checks `panel?.isVisible`. If visible, `makeKeyAndOrderFront(nil)` to bring forward. Don't reset fields.                                                                                                                                 |
| 3   | Hotkey fires in rapid succession                | Idempotent via #2. No debouncing needed.                                                                                                                                                                                                               |
| 4   | Quick Notes folder deleted while panel has text | Detected at save time. Transparent recreation, no user-visible error.                                                                                                                                                                                  |
| 5   | Main Jot window closed when hotkey fires        | Works fine. Panel independent of main window; `SimpleSwiftDataManager.shared` keeps data alive.                                                                                                                                                        |
| 6   | Hotkey fires mid-launch                         | `install()` runs at end of `JotApp.init`; hotkey isn't registered until then. Zero risk.                                                                                                                                                               |
| 7   | Multiple displays                               | `panel.center()` centers on `NSScreen.main` (screen containing cursor). Subsequent shows honor frame autosave.                                                                                                                                         |
| 8   | Unsaved body text + Escape                      | Silent discard. Quick notes are a stream; no confirmation dialog.                                                                                                                                                                                      |
| 9   | Unsaved body text + force-quit                  | Not persisted. v1 keeps panel state in memory only.                                                                                                                                                                                                    |
| 10  | Hotkey cleared in Settings                      | Button label flips to "Click to record". Unambiguous.                                                                                                                                                                                                  |
| 11  | Settings hot-swap while panel is open           | Open panel keeps working; only _next_ show uses new chord.                                                                                                                                                                                             |

---

## Error handling principles

- No `fatalError` in new code
- Carbon `OSStatus` failures → `Logger` warning + user-visible recovery
- `addNote` already has built-in error recovery (returns transient `Note` on DB failure); inherit
- No `try!`

---

## Testing

### Unit tests (`JotTests/QuickNoteTests.swift`)

1. `QuickNoteHotKey` Codable round-trip (encode → decode → equal)
2. Cocoa modifier mask → Carbon modifier mask, all 16 combinations of ⌃⌥⇧⌘
3. Carbon modifier mask → display string (correctly ordered ⌃⌥⇧⌘)
4. `QuickNoteService.save` with empty title + non-empty body → title from first line, truncated
5. `QuickNoteService.save` with empty title + empty body → title = `"Quick Note"`
6. `resolveOrCreateQuickNotesFolder` — first call creates + persists; second call returns same ID; stale ID triggers recreate

### Manual smoke checklist

- [ ] Press default chord in Safari → panel appears, Safari stays frontmost
- [ ] Type + ⌘↩ → note appears in Jot sidebar under "Quick Notes" folder
- [ ] Press chord again while panel visible → panel stays, focus returns to panel
- [ ] Change chord in Settings → old chord dead, new chord live
- [ ] Quit + relaunch Jot → chord still live after relaunch
- [ ] Delete Quick Notes folder manually → next save recreates it
- [ ] Clear hotkey in Settings → chord no longer fires anything
- [ ] Re-bind after clear → new chord works

### What cannot be unit-tested

Actual Carbon hotkey firing (requires WindowServer). Covered by the manual smoke checklist.

---

## Out of scope (deferred)

- Draft autosave (panel state persistence across force-quit)
- Click-outside-to-dismiss
- Multiple hotkeys (e.g., second hotkey that opens the main window to a specific folder)
- Rich text, attachments, checklists in the quick panel
- Picking a non-default destination folder in Settings
- Collision detection against known system shortcuts before installing (we rely on `RegisterEventHotKey` returning an error)
- Analytics / usage metrics