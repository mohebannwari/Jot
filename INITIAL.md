# Batch 1: Comprehensive Keyboard Shortcuts + Toast-based Undo

## What We're Building

Two foundational features for Jot that improve keyboard-driven workflows and add safety nets for destructive operations.

---

## Feature 1: Comprehensive Keyboard Shortcuts (DES-265)

### Current State
The app has basic formatting shortcuts (Cmd+B/I/U, Cmd+Z/Shift+Z, Cmd+1/2/3 for headings, Cmd+Shift+8/7 for lists, Cmd+Shift+X/H/K for strikethrough/highlight/link) all handled in `TodoEditorRepresentable.swift` via `performKeyEquivalent` and `keyDown`. Global shortcuts exist for Cmd+F (find), Cmd+H (replace), Cmd+Shift+F/Cmd+K (search), Cmd+S (save), Cmd+. (toggle sidebar) in `ContentView.swift`. A selection menu in `NoteSelectionCommands.swift` covers Cmd+A (select all), Delete (delete selected), Cmd+Shift+E (export), Cmd+Shift+M (move).

### What's Missing

**Note Management:**
- Cmd+N -- Create new note (no shortcut exists)
- Cmd+Shift+N -- Create new folder (no shortcut exists)
- Cmd+Backspace -- Move selected note to trash (Delete key works in selection mode but not for single focused note)

**Formatting (already exists, verify/enhance):**
- Cmd+1/2/3 -- Headings (EXISTS in TodoEditorRepresentable line 7435-7441)
- Cmd+Shift+L -- Toggle bulleted list (currently Cmd+Shift+8, add Cmd+Shift+L as alias)
- Cmd+Shift+O -- Toggle numbered list (currently Cmd+Shift+7, add alias)
- Cmd+L -- Insert link (currently Cmd+Shift+K, also add Cmd+L)
- Cmd+Shift+X -- Strikethrough (EXISTS)
- Cmd+Shift+H -- Highlight (EXISTS)

**Navigation:**
- Up/Down arrow in sidebar to navigate between notes (no keyboard nav exists in sidebar)
- Cmd+Shift+] / Cmd+Shift+[ -- Next/previous note (alternative navigation)

**Editor:**
- Tab/Shift+Tab -- Increase/decrease indent (verify if exists)
- Cmd+Shift+. -- Block quote (EXISTS at line 7465)

### Implementation Approach
- Add new note/folder commands to the menu bar via `CommandGroup` in JotApp.swift or ContentView.swift
- Sidebar keyboard nav needs focus state management -- when sidebar is focused, arrow keys move note selection
- Format shortcuts that already exist just need menu bar visibility for discoverability
- All new shortcuts must use `.keyboardShortcut()` SwiftUI modifiers for menu items

### Key Files
- `Jot/App/ContentView.swift` -- menu bar, sidebar, note management actions
- `Jot/App/JotApp.swift` -- CommandGroup definitions
- `Jot/App/NoteSelectionCommands.swift` -- selection-related commands
- `Jot/Views/Components/TodoEditorRepresentable.swift` -- editor key handling (performKeyEquivalent, keyDown at lines 7401-7480)

---

## Feature 2: Toast-based Undo for Destructive Operations (DES-266)

### Current State
No toast/notification system exists. No app-level undo beyond NSTextView's built-in undo for text edits. Destructive operations execute immediately with no undo path except manual reversal (e.g., restore from trash).

### Operations That Need Undo Toasts

| Operation | Function | File | Reverse |
|-----------|----------|------|---------|
| Delete (trash) | `moveToTrash(ids:)` line 501 | SimpleSwiftDataManager | `restoreFromTrash(ids:)` |
| Archive | `archiveNotes(ids:)` line 420 | SimpleSwiftDataManager | `unarchiveNotes(ids:)` |
| Pin/Unpin | `togglePin(id:)` line 659 | SimpleSwiftDataManager | `togglePin(id:)` again |
| Move to folder | `moveNotes(ids:toFolderID:)` line 862 | SimpleSwiftDataManager | `moveNotes(ids:toFolderID: originalFolderID)` |
| Delete folder | `deleteFolder(id:)` line 787 | SimpleSwiftDataManager | Recreate folder + reassign notes |
| Archive folder | `archiveFolder(_:)` line 270 | SimpleSwiftDataManager | `unarchiveFolder(_:)` |

### Design Requirements
- Floating pill/toast at the bottom-center of the window
- Shows operation description + "Undo" button
- Auto-dismisses after 5 seconds
- Latest action replaces previous toast (no stacking)
- Liquid Glass styling consistent with app design
- Smooth enter/exit animation using `.jotSpring` pattern

### Implementation Approach
- New `UndoToastManager` as `@Observable` class, injected as `@EnvironmentObject`
- New `UndoToast` SwiftUI view with Liquid Glass material
- Each destructive action captures the undo closure BEFORE executing
- Toast manager holds the current toast (message + undo closure + timer)
- Overlay placed in ContentView's ZStack (same level as other floating elements)
- Timer auto-dismisses; clicking Undo executes closure and dismisses

### Animation
- Enter: `.transition(.move(edge: .bottom).combined(with: .opacity))` with `.jotSpring`
- Exit: same transition reversed
- Toast should not interfere with other floating UI (search, toolbar, settings)

### Key Files
- New: `Jot/Utils/UndoToastManager.swift`
- New: `Jot/Views/Components/UndoToast.swift`
- Modified: `Jot/App/ContentView.swift` -- overlay placement + integrate with delete/archive/pin/move actions
- Modified: `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` -- no changes needed here, undo closures call existing reverse functions

### Existing Patterns to Follow
- Animation: `withAnimation(.jotSpring)` and `.transition(.scale.combined(with: .opacity))`
- Glass styling: `GlassEffects.swift` helpers (`liquidGlass(in:)`, `tintedLiquidGlass(in:tint:)`)
- Overlay placement: same pattern as `FloatingSearch`, `FloatingToolbar`

---

## Acceptance Criteria

### Keyboard Shortcuts
- [ ] Cmd+N creates a new note
- [ ] Cmd+Shift+N creates a new folder
- [ ] Cmd+Backspace moves focused note to trash
- [ ] Arrow keys navigate notes in sidebar when sidebar is focused
- [ ] All formatting shortcuts visible in menu bar for discoverability
- [ ] No conflicts with existing system or app shortcuts

### Toast Undo
- [ ] Toast appears after: delete, archive, pin/unpin, move to folder, delete folder, archive folder
- [ ] Clicking "Undo" reverses the operation correctly
- [ ] Toast auto-dismisses after 5 seconds
- [ ] New action replaces previous toast
- [ ] Liquid Glass styling matches app design
- [ ] Animation is smooth (enter/exit)
- [ ] Toast doesn't block other floating UI elements

---

## Out of Scope
- Customizable keyboard shortcuts (future feature)
- Multiple undo (only most recent operation)
- Undo for permanent delete (intentionally irreversible)
