# Multi-Split System Design

## Overview

Replace the single-split architecture with a multi-split system where users can create unlimited independent split sessions. Only one split is visible at a time in the detail area; the sidebar lists all active splits and allows switching between them.

## Data Model

```swift
struct SplitSession: Identifiable {
    let id = UUID()
    var primaryNoteID: UUID?    // nil = still picking
    var secondaryNoteID: UUID?  // nil = still picking
    var position: SplitPosition = .right
    var ratio: CGFloat = 0.5
}
```

### State (replaces flat split state)

| New | Replaces |
|-----|----------|
| `splitSessions: [SplitSession]` | `splitNote`, `splitPrimaryNoteID`, `splitPosition`, `splitRatio` |
| `activeSplitID: UUID?` | Implicit (there was only one) |
| `pendingSplitID: UUID?` | `isSplitPicking` |

Retained as-is: `isSplitViewVisible`, `splitDragDelta`, `splitPickerOverlayPane`, editor IDs.

### Computed Properties

- `activeSplit: SplitSession?` — lookup by `activeSplitID`
- `isSplitActive: Bool` — `!splitSessions.isEmpty`
- `shouldShowSplitLayout: Bool` — `activeSplitID != nil && isSplitViewVisible`
- `isPendingSplit: Bool` — `pendingSplitID != nil`

## Sidebar Layout

```
Active Split              <- header (visible when splitSessions.count > 0)

[Split 1 container]       <- white bg, 12px radius, shadow (completed splits only)
  Note A        28.02
  ~~wavy~~
  Note B        22.02

        8px gap           <- between containers

[Split 2 container]
  Note C        25.02
  ~~wavy~~
  Note D        27.02

        4px gap           <- between last container and button

[--- + ---]               <- dashed pill button (or "Cancel" when pending)
```

### Add Button

- Dashed border: 1px dashed, color `#d6d3d1` (light) / dark variant
- Padding: 4px all sides
- Border radius: 999 (full capsule)
- Centered `+` icon: 18x18 `IconPlusSmall`
- Full width of sidebar content area
- When `pendingSplitID != nil`: changes to "Cancel" text, same dashed pill container

### Active Split Container

- Same as current: white/dark fill, 12px radius, dual shadow
- Wavy divider between notes
- Clicking navigates to that split (`activeSplitID = session.id`, `isSplitViewVisible = true`)

## Detail Panes — Creation Mode

When a new split is being created (both note IDs nil):

### Pane Styling
- **No fill** — fully transparent, app window background visible
- **3px dashed border**, `#d6d3d1`, corner radius 12px
- Content: note picker list ("Select a note", search field, note rows)
- No "Close splitview" button (that only exists in the original single-split initial flow)

### Drag Handle
- Standard pill: 4px wide x 18px tall, `#44403c`, radius 999
- Positioned between the two panes (same as current split handle)

### Transition
Once both notes are selected:
- `pendingSplitID` cleared
- Panes transition to solid-background `NoteDetailView` rendering
- Active Split container appears in sidebar

## Interactions

### Creating a Split
1. User taps "+" button
2. New `SplitSession` appended with both note IDs nil
3. `pendingSplitID` and `activeSplitID` set to new session's ID
4. `isSplitViewVisible = true`
5. Detail area shows two dashed-border panes with note pickers
6. "+" becomes "Cancel"
7. User picks first note -> that pane's ID is set, other still shows picker
8. User picks second note -> both IDs set, `pendingSplitID` cleared, split complete

### Canceling
1. User taps "Cancel"
2. Pending session removed from array
3. If previous active split exists, switch to it; otherwise single-note mode

### Switching Splits
- Click Active Split container in sidebar -> `activeSplitID = session.id`, `isSplitViewVisible = true`
- Click a regular note -> `isSplitViewVisible = false`, show single note
- Split data persists in background

### Closing a Split
- Per-pane close icons work as before
- Remove session from `splitSessions`
- If it was active, fall back to next session or single-note mode

### Per-Pane Controls
- Flashcards (switch note overlay), move, close icons — identical to current
- Operate on `splitSessions[activeSplitID]` instead of flat state

## Migration Path

All existing split functions refactored to operate on `SplitSession` lookups:

| Function | Change |
|----------|--------|
| `openSplit(position:)` | Creates new `SplitSession`, appends to array |
| `closeSplit()` | Removes session from array |
| `moveSplitToOtherSide()` | Swaps primary/secondary IDs in active session |
| `closeLeftSplit()` / `closeRightSplit()` | Removes session, promotes surviving note |
| `splitDetailLayout(...)` | Reads from active session instead of flat state |
| `secondaryPaneContent(...)` | Reads from active session |
| `activeSplitSidebarSection` | Iterates `splitSessions`, renders container per completed session |
| `splitPaneControls(...)` | Unchanged API, operates on active session |
| `splitPickerOverlayView(...)` | Unchanged API, operates on active session |

## New Asset

`IconPlusSmall` — 18x18 viewBox, stroke-based `+` icon, `currentColor`, matching existing icon family stroke weight (1.5). Needs imageset with `template-rendering-intent` and `preserves-vector-representation`.
