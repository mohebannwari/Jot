# Product Requirements Prompt: Batch 1 — Keyboard Shortcuts + Toast Undo

## Metadata
- **Created**: 2026-03-20
- **Target OS**: macOS 26+
- **Confidence**: 9/10
- **Estimated Complexity**: Medium
- **Linear Issues**: DES-265, DES-266
- **Branch**: `feature/batch-1-shortcuts-undo`

---

## 1. Feature Overview

### Purpose
Add comprehensive keyboard shortcuts for note management, formatting, and navigation, plus a toast-based undo system for destructive operations. These are foundational UX improvements -- shortcuts make the app keyboard-first, and undo toasts provide a safety net reused by every future feature.

### User Stories
- As a power user, I want to create notes, navigate, and format without reaching for the mouse.
- As any user, I want to undo accidental deletes/moves/archives instantly via a toast notification.

### Key Requirements
- Cmd+N creates a new note
- Cmd+Shift+N creates a new folder
- Cmd+Backspace trashes the focused note
- Arrow keys navigate notes in the sidebar
- All formatting shortcuts discoverable in the menu bar
- Floating undo toast appears after destructive operations (delete, archive, pin, move, folder delete/archive)
- Toast auto-dismisses after 5 seconds
- Clicking "Undo" reverses the operation

---

## 2. Context & Background

### Existing Architecture

**Keyboard handling is split across two systems:**
1. **SwiftUI `.keyboardShortcut()` modifiers** -- used in `ContentView.swift` (Cmd+F, Cmd+H, Cmd+Shift+F, Cmd+K, Cmd+S, Cmd+.) and `NoteSelectionCommands.swift` (Cmd+A, Delete, Cmd+Shift+E, Cmd+Shift+M)
2. **AppKit `performKeyEquivalent` + `keyDown`** -- used in `TodoEditorRepresentable.swift` for text formatting (Cmd+1/2/3, Cmd+Shift+8/7/X/H/K/.) and menu navigation (arrow keys for command menu, note picker, URL paste)

**Menu bar** is defined in `JotApp.swift` via `.commands { }` block. Currently has:
- `NoteSelectionCommands()` -- a `CommandMenu("Selection")` with select/delete/export/move
- `CommandGroup(replacing: .appSettings)` -- Settings shortcut

**No toast/notification system exists.** No app-level undo beyond NSTextView's built-in text undo.

**Related Components:**
- `SimpleSwiftDataManager` -- all CRUD operations, holds `notes` and `folders` arrays
- `ContentView.swift` -- sidebar, overlay system, destructive action wrappers
- `NoteSelectionCommands.swift` -- existing menu commands via NotificationCenter
- `GlassEffects.swift` -- Liquid Glass helpers
- `Extensions.swift` -- animation definitions (`.jotSpring`, `.jotBounce`, etc.)

**State Management:**
- Managers injected as `@EnvironmentObject` in JotApp: `notesManager`, `themeManager`, `authManager`
- New `UndoToastManager` follows same pattern

**Data Flow:**
```
Keyboard Shortcut → Menu Command / Direct Action → NotesManager CRUD → UI Update
Destructive Action → Capture undo closure → Execute action → Show toast → (Undo or dismiss)
```

### Dependencies
**Internal:**
- `SimpleSwiftDataManager` -- `moveToTrash()`, `restoreFromTrash()`, `archiveNotes()`, `unarchiveNotes()`, `togglePin()`, `moveNotes()`, `deleteFolder()`, `archiveFolder()`, `unarchiveFolder()`
- `GlassEffects.swift` -- `thinLiquidGlass(in:)` for toast styling
- `Extensions.swift` -- `.jotSpring` animation

**External:**
- SwiftUI `Commands`, `CommandGroup`, `CommandMenu`
- Foundation `NotificationCenter` (existing pattern for menu → action communication)

---

## 3. Architecture & Design Patterns

### File Structure
```
Jot/
├── App/
│   ├── JotApp.swift                    # MODIFY — add new CommandGroups
│   ├── ContentView.swift               # MODIFY — overlay, action wrappers, sidebar nav
│   └── NoteSelectionCommands.swift     # MODIFY — extend with new commands
├── Views/
│   └── Components/
│       └── UndoToast.swift             # CREATE — toast view component
└── Utils/
    └── UndoToastManager.swift          # CREATE — toast state manager
```

### UndoToastManager Pattern
```swift
import SwiftUI

@MainActor
final class UndoToastManager: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undoAction: () -> Void
    }

    @Published var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, undoAction: @escaping () -> Void) {
        dismissTask?.cancel()
        withAnimation(.jotSpring) {
            currentToast = Toast(message: message, undoAction: undoAction)
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func performUndo() {
        currentToast?.undoAction()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.jotSpring) {
            currentToast = nil
        }
    }
}
```

### UndoToast View Pattern
```swift
struct UndoToast: View {
    @EnvironmentObject private var undoManager: UndoToastManager

    var body: some View {
        if let toast = undoManager.currentToast {
            HStack(spacing: 12) {
                Text(toast.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Button("Undo") {
                    undoManager.performUndo()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .thinLiquidGlass(in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
```

### Integration Pattern (in destructive actions)
```swift
// Before executing delete:
let noteNames = noteIDs.compactMap { id in
    notesManager.notes.first { $0.id == id }?.title
}
let message = noteIDs.count == 1
    ? "Moved \"\(noteNames.first ?? "Note")\" to trash"
    : "Moved \(noteIDs.count) notes to trash"

// Capture state for undo BEFORE mutation
let idsToRestore = noteIDs

// Execute the action
deleteNotesNow(noteIDs)

// Show toast with undo
undoToastManager.show(message) { [weak notesManager] in
    notesManager?.restoreFromTrash(ids: idsToRestore)
}
```

---

## 4. Design System Compliance

### Liquid Glass Effects
- Toast uses `thinLiquidGlass(in: Capsule())` -- non-interactive, floating overlay
- No glass-on-glass (toast floats above content, not above other glass)

### Colors
- Text: `.primary` (adapts to light/dark)
- Undo button: `.accent` or `Color.accentColor`
- No hardcoded color values

### Typography
- Toast message: `.system(size: 13, weight: .medium)`
- Undo button: `.system(size: 13, weight: .semibold)`

### Spacing
- Toast internal: horizontal 16, vertical 10
- Toast offset from bottom: 24

### Animations
- Enter/exit: `.jotSpring` with `.transition(.move(edge: .bottom).combined(with: .opacity))`
- State changes: `withAnimation(.jotSpring)`

---

## 5. Implementation Steps

### Step 1: Create UndoToastManager
**Objective:** Build the state management for the toast system.

**Files to Create:**
- `Jot/Utils/UndoToastManager.swift`

**Implementation:**
- `@MainActor final class UndoToastManager: ObservableObject`
- `@Published var currentToast: Toast?`
- `show(_:undoAction:)` -- cancels previous toast, sets new one, starts 5s timer
- `performUndo()` -- executes undo closure, dismisses
- `dismiss()` -- cancels timer, nils toast
- Timer via `Task.sleep` (cancellable)

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

**Success Criteria:**
- [ ] Builds without errors
- [ ] Manager holds one toast at a time
- [ ] Timer auto-dismisses after 5 seconds

---

### Step 2: Create UndoToast View
**Objective:** Build the floating toast UI component.

**Files to Create:**
- `Jot/Views/Components/UndoToast.swift`

**Implementation:**
- Reads from `UndoToastManager` via `@EnvironmentObject`
- HStack: message text + "Undo" button
- `thinLiquidGlass(in: Capsule())` background
- Transition: `.move(edge: .bottom).combined(with: .opacity)`
- Tapping "Undo" calls `undoManager.performUndo()`

**Success Criteria:**
- [ ] Follows component structure pattern
- [ ] Uses Liquid Glass correctly
- [ ] Animations match app style

---

### Step 3: Inject UndoToastManager and Place Toast Overlay
**Objective:** Wire the toast into the app's view hierarchy.

**Files to Modify:**
- `Jot/App/JotApp.swift` -- add `@StateObject private var undoToastManager = UndoToastManager()` and `.environmentObject(undoToastManager)`
- `Jot/App/ContentView.swift` -- add `@EnvironmentObject private var undoToastManager: UndoToastManager`, place `UndoToast()` as an overlay at the bottom of the main ZStack (same level as search/trash overlays)

**Overlay Placement:**
```swift
// In ContentView body, after other overlays:
.overlay(alignment: .bottom) {
    UndoToast()
        .padding(.bottom, 24)
}
```

**Success Criteria:**
- [ ] Toast renders at bottom-center of window
- [ ] Doesn't interfere with other overlays (search, trash, settings)
- [ ] EnvironmentObject accessible throughout view hierarchy

---

### Step 4: Integrate Toast with Destructive Operations
**Objective:** Hook every destructive action to show an undo toast.

**Files to Modify:**
- `Jot/App/ContentView.swift` -- modify `deleteNotesNow()`, `archiveNotes()`, `setPinState()`, `moveNotesToFolder()`, and any folder delete/archive functions

**Operations to integrate:**

1. **Delete notes (trash):**
   - Capture `noteIDs` before delete
   - After `deleteNotesNow()`, show toast "Moved N note(s) to trash"
   - Undo calls `notesManager.restoreFromTrash(ids:)`

2. **Archive notes:**
   - Capture `noteIDs` before archive
   - After `archiveNotes()`, show toast "Archived N note(s)"
   - Undo calls `notesManager.unarchiveNotes(ids:)`

3. **Pin/Unpin:**
   - Capture note ID and previous pin state
   - After toggle, show toast "Pinned/Unpinned note"
   - Undo calls `notesManager.togglePin(id:)` again

4. **Move to folder:**
   - Capture `noteIDs` and their `originalFolderIDs` before move
   - After move, show toast "Moved N note(s) to FolderName"
   - Undo moves each note back to its original folder

5. **Delete folder:**
   - Capture folder data (name, ID, color) and note IDs in that folder
   - After delete, show toast "Deleted folder FolderName"
   - Undo recreates folder and moves notes back

6. **Archive folder:**
   - Capture folder reference
   - After archive, show toast "Archived folder FolderName"
   - Undo calls `notesManager.unarchiveFolder()`

**Success Criteria:**
- [ ] All 6 operations show toast
- [ ] All 6 undo actions correctly reverse the operation
- [ ] Toast message is contextual (includes note/folder name or count)

---

### Step 5: Add Menu Bar Commands for Note Management
**Objective:** Add Cmd+N, Cmd+Shift+N, and Cmd+Backspace as discoverable menu items.

**Files to Modify:**
- `Jot/App/JotApp.swift` -- add new `CommandGroup` or `CommandMenu` for note management
- `Jot/App/ContentView.swift` -- handle notification-based actions (same pattern as `NoteSelectionCommands`)

**New Commands:**
```swift
CommandGroup(replacing: .newItem) {
    Button("New Note") {
        NotificationCenter.default.post(name: .createNewNote, object: nil)
    }
    .keyboardShortcut("n", modifiers: .command)

    Button("New Folder") {
        NotificationCenter.default.post(name: .createNewFolder, object: nil)
    }
    .keyboardShortcut("n", modifiers: [.command, .shift])

    Divider()

    Button("Move to Trash") {
        NotificationCenter.default.post(name: .trashFocusedNote, object: nil)
    }
    .keyboardShortcut(.delete, modifiers: .command)
}
```

**ContentView handlers:**
- `.onReceive(.createNewNote)` -- call existing new note creation logic
- `.onReceive(.createNewFolder)` -- call existing new folder creation logic
- `.onReceive(.trashFocusedNote)` -- delete the currently selected/focused note

**Success Criteria:**
- [ ] Cmd+N creates a new note
- [ ] Cmd+Shift+N creates a new folder
- [ ] Cmd+Backspace trashes the focused note
- [ ] All three appear in the menu bar under File (or equivalent)

---

### Step 6: Add Formatting Shortcut Aliases and Menu Visibility
**Objective:** Make existing formatting shortcuts discoverable via menu bar and add common aliases.

**Files to Modify:**
- `Jot/App/JotApp.swift` -- add Format menu with formatting commands

**New Format Menu:**
```swift
CommandMenu("Format") {
    Button("Bold") { post(.bold) }
        .keyboardShortcut("b", modifiers: .command)
    Button("Italic") { post(.italic) }
        .keyboardShortcut("i", modifiers: .command)
    Button("Underline") { post(.underline) }
        .keyboardShortcut("u", modifiers: .command)
    Button("Strikethrough") { post(.strikethrough) }
        .keyboardShortcut("x", modifiers: [.command, .shift])

    Divider()

    Button("Heading 1") { post(.h1) }
        .keyboardShortcut("1", modifiers: .command)
    Button("Heading 2") { post(.h2) }
        .keyboardShortcut("2", modifiers: .command)
    Button("Heading 3") { post(.h3) }
        .keyboardShortcut("3", modifiers: .command)

    Divider()

    Button("Bullet List") { post(.bulletList) }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    Button("Numbered List") { post(.numberedList) }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    Button("Block Quote") { post(.blockQuote) }
        .keyboardShortcut(".", modifiers: [.command, .shift])

    Divider()

    Button("Highlight") { post(.highlight) }
        .keyboardShortcut("h", modifiers: [.command, .shift])
    Button("Insert Link") { post(.insertLink) }
        .keyboardShortcut("k", modifiers: [.command, .shift])
}
```

**Important:** These menu shortcuts may conflict with the AppKit `keyDown` handler in `TodoEditorRepresentable`. The AppKit handler fires first in the responder chain. The menu items serve as **discoverability** -- the actual key handling remains in AppKit. Verify no double-firing occurs.

**Success Criteria:**
- [ ] Format menu appears in menu bar
- [ ] All formatting shortcuts listed with correct key combos
- [ ] No double-firing between menu and AppKit handler

---

### Step 7: Sidebar Arrow Key Navigation
**Objective:** Enable up/down arrow keys to navigate between notes when the sidebar is focused.

**Files to Modify:**
- `Jot/App/ContentView.swift` -- add keyboard navigation to the sidebar note list

**Implementation Approach:**
- Track `focusedNoteIndex` state
- When sidebar is in focus, intercept up/down arrow keys
- Up arrow selects previous note, down arrow selects next
- Selection follows the current filter/sort order
- Wrap around at boundaries (optional -- or stop at edges)

**Consideration:** SwiftUI's `List` with `.focusable()` and `@FocusState` may handle this natively. Investigate before custom implementation. If the sidebar uses `ScrollView` + `LazyVStack` instead of `List`, manual handling is needed.

**Success Criteria:**
- [ ] Arrow keys move selection up/down in sidebar
- [ ] Selected note opens in editor
- [ ] Works with all sort/filter modes
- [ ] Doesn't conflict with editor arrow keys (only when sidebar is focused)

---

### Step 8: Write Tests
**Objective:** Test UndoToastManager logic and keyboard command notifications.

**Files to Create:**
- `JotTests/UndoToastManagerTests.swift`

**Test Cases:**
```swift
@MainActor
func testShowToastSetsCurrentToast() {
    let manager = UndoToastManager()
    manager.show("Test message") { }
    XCTAssertNotNil(manager.currentToast)
    XCTAssertEqual(manager.currentToast?.message, "Test message")
}

@MainActor
func testPerformUndoExecutesClosureAndDismisses() {
    let manager = UndoToastManager()
    var undoCalled = false
    manager.show("Test") { undoCalled = true }
    manager.performUndo()
    XCTAssertTrue(undoCalled)
    XCTAssertNil(manager.currentToast)
}

@MainActor
func testDismissClearsToast() {
    let manager = UndoToastManager()
    manager.show("Test") { }
    manager.dismiss()
    XCTAssertNil(manager.currentToast)
}

@MainActor
func testNewToastReplacesOld() {
    let manager = UndoToastManager()
    manager.show("First") { }
    manager.show("Second") { }
    XCTAssertEqual(manager.currentToast?.message, "Second")
}
```

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

---

## 6. Success Criteria

### Functional Requirements
- [ ] Cmd+N creates a new note
- [ ] Cmd+Shift+N creates a new folder
- [ ] Cmd+Backspace trashes focused note
- [ ] Arrow keys navigate sidebar notes
- [ ] Format menu shows all formatting shortcuts
- [ ] Toast appears after all 6 destructive operations
- [ ] Undo button reverses each operation correctly
- [ ] Toast auto-dismisses after 5 seconds
- [ ] New toast replaces previous toast

### Design System Compliance
- [ ] Toast uses `thinLiquidGlass(in: Capsule())`
- [ ] No glass-on-glass violations
- [ ] Semantic colors only (no hardcoded)
- [ ] Typography: system 13 medium/semibold
- [ ] Animation uses `.jotSpring`
- [ ] Transition: `.move(edge: .bottom).combined(with: .opacity)`

### Code Quality
- [ ] `UndoToastManager` follows existing manager patterns
- [ ] `UndoToast` follows component structure (props → state → body)
- [ ] Notification-based command pattern matches `NoteSelectionCommands`
- [ ] No responder chain conflicts

### Testing
- [ ] UndoToastManager unit tests pass
- [ ] Full test suite passes
- [ ] Manual verification of all shortcuts and undo operations

---

## 7. Validation Gates

### Build Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

### Test Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

---

## 8. Gotchas & Considerations

### Keyboard Shortcut Conflicts
- **Cmd+H** is macOS system "Hide App" -- currently used for Find & Replace. Verify behavior.
- **Cmd+N** may conflict if macOS reserves it for "New Window" in DocumentGroup apps. Jot uses `WindowGroup`, so `CommandGroup(replacing: .newItem)` should claim it.
- **Cmd+L** is used in Safari for URL bar -- no conflict within Jot.
- **Cmd+A** already has dual behavior (select all notes in sidebar vs select all text in editor). Verify responder chain priority.

### Responder Chain Priority
SwiftUI menu `.keyboardShortcut()` and AppKit `performKeyEquivalent` both intercept key events. The AppKit handler in `TodoEditorRepresentable` fires FIRST when the editor is focused. Menu items fire when no responder claims the event. This means:
- Formatting shortcuts (Cmd+1/2/3, etc.) are handled by AppKit when editor is focused -- good
- New note/folder shortcuts (Cmd+N, Cmd+Shift+N) should be handled by the menu -- good, since they're not editor-specific

### Undo Closure Capture
- Closures must capture state BEFORE the mutation, not after
- Use `[weak notesManager]` to avoid retain cycles
- The `deleteFolder` undo is the most complex -- needs to recreate the folder entity AND reassign notes

### Toast vs Alert Interaction
- If a batch delete confirmation alert is showing, toast should NOT appear until the alert resolves
- Pin/unpin for notes in folders is silently ignored by `togglePin()` -- toast should not show for no-op operations

---

## 9. Implementation Checklist

- [ ] Read entire PRP
- [ ] Step 1: Create UndoToastManager
- [ ] Step 2: Create UndoToast view
- [ ] Step 3: Inject manager, place overlay
- [ ] Build validation
- [ ] Step 4: Integrate with all destructive operations
- [ ] Build validation
- [ ] Step 5: Add note management menu commands
- [ ] Step 6: Add formatting menu for discoverability
- [ ] Step 7: Sidebar arrow key navigation
- [ ] Build validation
- [ ] Step 8: Write and run tests
- [ ] Test validation
- [ ] Manual testing of all shortcuts and undo operations
- [ ] Verify no shortcut conflicts

---

## 10. Confidence Assessment

**Confidence Level:** 9/10

**What's Clear:**
- All existing shortcut locations and patterns are mapped
- All destructive operations identified with exact function signatures
- Overlay placement pattern understood
- EnvironmentObject injection pattern established
- Animation and glass effect patterns documented

**What Needs Verification During Implementation:**
- Responder chain priority between SwiftUI menu commands and AppKit keyDown
- Whether sidebar uses `List` (native focus) or `ScrollView` (manual nav needed)
- Whether `CommandGroup(replacing: .newItem)` works correctly in `WindowGroup` context
