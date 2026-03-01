# Multi-Split System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single-split architecture with an array-based multi-split system where users create unlimited independent split sessions, each visible one at a time.

**Architecture:** Introduce a `SplitSession` struct holding note IDs + layout config. Replace flat `@State` properties (`splitNote`, `splitPrimaryNoteID`, `splitPosition`, `splitRatio`, `isSplitPicking`) with `splitSessions: [SplitSession]`, `activeSplitID: UUID?`, and `pendingSplitID: UUID?`. All existing split functions become lookups against the active session. The sidebar renders one container per completed split plus a dashed "+" button.

**Tech Stack:** SwiftUI (macOS 26+), Liquid Glass design system, SVG icon assets

**Design doc:** `docs/plans/2026-02-28-multi-split-design.md`

---

### Task 1: Create `IconPlusSmall` Asset

**Files:**
- Create: `Jot/Assets.xcassets/IconPlusSmall.imageset/IconPlusSmall.svg`
- Create: `Jot/Assets.xcassets/IconPlusSmall.imageset/Contents.json`

**Step 1: Create the SVG**

18x18 viewBox, stroke-width 1.5, `currentColor`, round linecaps/linejoins. Simple `+` shape:

```svg
<svg width="18" height="18" viewBox="0 0 18 18" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M9 3.75V14.25" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M3.75 9H14.25" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

**Step 2: Create Contents.json**

```json
{
  "images": [
    { "filename": "IconPlusSmall.svg", "idiom": "universal", "scale": "1x" },
    { "idiom": "universal", "scale": "2x" },
    { "idiom": "universal", "scale": "3x" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "template-rendering-intent": "template",
    "preserves-vector-representation": true
  }
}
```

**Step 3: Build to verify asset compiles**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Jot/Assets.xcassets/IconPlusSmall.imageset/
git commit -m "feat: add IconPlusSmall asset for multi-split add button"
```

---

### Task 2: Define `SplitSession` Struct

**Files:**
- Modify: `Jot/App/ContentView.swift:11-12` (add struct near existing enums)

**Step 1: Add the struct**

At line 11, after `enum SplitPosition`, before `enum SplitPickerPane`, add:

```swift
struct SplitSession: Identifiable, Equatable {
    let id: UUID
    var primaryNoteID: UUID?
    var secondaryNoteID: UUID?
    var position: SplitPosition = .right
    var ratio: CGFloat = 0.5

    init(id: UUID = UUID(), primaryNoteID: UUID? = nil, secondaryNoteID: UUID? = nil) {
        self.id = id
        self.primaryNoteID = primaryNoteID
        self.secondaryNoteID = secondaryNoteID
    }

    var isComplete: Bool { primaryNoteID != nil && secondaryNoteID != nil }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Jot/App/ContentView.swift
git commit -m "feat: add SplitSession struct for multi-split data model"
```

---

### Task 3: Replace Flat Split State with Array-Based State

This is the core migration. Replace individual `@State` properties with the array + active-ID pattern, then update all computed properties and functions to use the new state.

**Files:**
- Modify: `Jot/App/ContentView.swift:104-118` (state vars)
- Modify: `Jot/App/ContentView.swift:176-201` (computed properties)

**Step 1: Replace state variables**

Remove these `@State` properties (lines 105-110):
```swift
// REMOVE:
@State private var splitNote: Note? = nil
@State private var splitPrimaryNoteID: UUID? = nil
@State private var isSplitPicking = false
@State private var splitPosition: SplitPosition = .right
@State private var splitRatio: CGFloat = 0.5
```

Add these in their place:
```swift
@State private var splitSessions: [SplitSession] = []
@State private var activeSplitID: UUID? = nil
@State private var pendingSplitID: UUID? = nil
```

Keep these unchanged: `isSplitMenuVisible`, `isSplitViewVisible`, `splitPickerOverlayPane`, `splitDragDelta`, `splitAiToolsState`, `splitFocusRequestID`, `splitEditorID`, `splitMenuButtonFrame`, `primaryEditorID`.

**Step 2: Update computed properties**

Replace `isSplitActive` (line 176):
```swift
private var isSplitActive: Bool { !splitSessions.isEmpty }
```

Replace `shouldShowSplitLayout` (lines 179-181):
```swift
private var shouldShowSplitLayout: Bool {
    activeSplitID != nil && isSplitViewVisible
}
```

Keep `sidebarActiveNoteID` and `sidebarSelectedNoteIDs` unchanged (they depend on `shouldShowSplitLayout` which still works).

Replace `splitPrimaryNote` (lines 198-201):
```swift
private var activeSplit: SplitSession? {
    guard let id = activeSplitID else { return nil }
    return splitSessions.first(where: { $0.id == id })
}

private var activeSplitIndex: Int? {
    guard let id = activeSplitID else { return nil }
    return splitSessions.firstIndex(where: { $0.id == id })
}

private var activePrimaryNote: Note? {
    guard let noteID = activeSplit?.primaryNoteID else { return nil }
    return notesManager.notes.first(where: { $0.id == noteID })
}

private var activeSecondaryNote: Note? {
    guard let noteID = activeSplit?.secondaryNoteID else { return nil }
    return notesManager.notes.first(where: { $0.id == noteID })
}

private var isActiveSplitPending: Bool {
    activeSplitID != nil && activeSplitID == pendingSplitID
}
```

**Step 3: Update `recentNotes` (lines 203-209)**

Keep the function but it now accepts a `Note` to exclude. No change needed — callers will pass the right note.

**Step 4: Build — expect errors**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep "error:" | head -20`

This WILL fail because many functions still reference `splitNote`, `splitPrimaryNoteID`, `isSplitPicking`, `splitPosition`, `splitRatio`. That's expected — Tasks 4-8 fix them.

**Step 5: Commit (even with errors — WIP checkpoint)**

```bash
git add Jot/App/ContentView.swift
git commit -m "wip: replace flat split state with SplitSession array (compile errors expected)"
```

---

### Task 4: Migrate Split Layout Functions

**Files:**
- Modify: `Jot/App/ContentView.swift` — `splitDetailLayout` (lines 506-565), `secondaryPaneContent` (lines 568-597)

**Step 1: Rewrite `splitDetailLayout`**

The function now reads position/ratio from the active session:

```swift
@ViewBuilder
private func splitDetailLayout(primaryNote: Note, totalWidth: CGFloat, cornerRadius: CGFloat) -> some View {
    let splitRadius = windowCornerRadius - windowContentPadding
    let position = activeSplit?.position ?? .right
    let ratio = activeSplit?.ratio ?? 0.5

    let availableForSplit = totalWidth - splitGap
    let baseSecW = availableForSplit * ratio
    let maxW = totalWidth - splitMinPaneWidth - splitGap
    let secW = max(splitMinPaneWidth, min(maxW, baseSecW + splitDragDelta)).rounded()
    let primW = (totalWidth - secW - splitGap).rounded()

    let isPending = isActiveSplitPending
    let hasPrimary = activeSplit?.primaryNoteID != nil
    let hasSecondary = activeSplit?.secondaryNoteID != nil

    if position == .right {
        HStack(spacing: 0) {
            // Left = primary
            if hasPrimary {
                singleNotePane(note: primaryNote, width: primW, cornerRadius: splitRadius)
                    .overlay(alignment: .topTrailing) {
                        if !isPending {
                            splitPaneControls(isLeftPane: true, isPrimaryPane: true)
                                .padding(.top, 12).padding(.trailing, 12)
                        }
                    }
                    .overlay {
                        splitPickerOverlayView(for: .primary, primaryNote: primaryNote)
                    }
            } else {
                splitPickerPane(width: primW, cornerRadius: splitRadius, excludingNote: activeSecondaryNote, isPrimary: true)
            }
            splitPaneResizeHandle(totalWidth: totalWidth)
            // Right = secondary
            if hasSecondary, let secNote = activeSecondaryNote {
                secondaryNotePane(note: secNote, width: secW, cornerRadius: splitRadius, primaryNote: primaryNote)
            } else {
                splitPickerPane(width: secW, cornerRadius: splitRadius, excludingNote: activePrimaryNote, isPrimary: false)
            }
        }
    } else {
        HStack(spacing: 0) {
            // Left = secondary
            if hasSecondary, let secNote = activeSecondaryNote {
                secondaryNotePane(note: secNote, width: secW, cornerRadius: splitRadius, primaryNote: primaryNote)
            } else {
                splitPickerPane(width: secW, cornerRadius: splitRadius, excludingNote: activePrimaryNote, isPrimary: false)
            }
            splitPaneResizeHandle(totalWidth: totalWidth)
            // Right = primary
            if hasPrimary {
                singleNotePane(note: primaryNote, width: primW, cornerRadius: splitRadius)
                    .overlay(alignment: .topTrailing) {
                        if !isPending {
                            splitPaneControls(isLeftPane: false, isPrimaryPane: true)
                                .padding(.top, 12).padding(.trailing, 12)
                        }
                    }
                    .overlay {
                        splitPickerOverlayView(for: .primary, primaryNote: primaryNote)
                    }
            } else {
                splitPickerPane(width: primW, cornerRadius: splitRadius, excludingNote: activeSecondaryNote, isPrimary: true)
            }
        }
    }
}
```

**Step 2: Add `splitPickerPane` — dashed border pane for creation mode**

New function — transparent pane with 3px dashed border, contains note picker:

```swift
@ViewBuilder
private func splitPickerPane(width: CGFloat, cornerRadius: CGFloat, excludingNote: Note?, isPrimary: Bool) -> some View {
    let excludeNote = excludingNote ?? Note(title: "", content: "")
    SplitNotePickerView(
        recentNotes: recentNotes(excluding: excludeNote),
        onSelect: { note in
            withAnimation(.jotSpring) {
                guard let idx = activeSplitIndex else { return }
                if isPrimary {
                    splitSessions[idx].primaryNoteID = note.id
                    selectedNote = note
                    selectedNoteIDs = [note.id]
                } else {
                    splitSessions[idx].secondaryNoteID = note.id
                }
                // If both are now set, clear pending
                if splitSessions[idx].isComplete {
                    pendingSplitID = nil
                }
            }
        },
        onClose: { cancelPendingSplit() }
    )
    .frame(width: width)
    .frame(maxHeight: .infinity)
    .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .foregroundColor(Color("BorderColor"))
    )
}
```

Note: `SplitNotePickerView` already has the "Close splitview" button. For multi-split creation, we should hide that. We'll handle this by adding an optional `showCloseButton` parameter to `SplitNotePickerView` in Task 6.

**Step 3: Add `secondaryNotePane` — extracted from old `secondaryPaneContent`**

```swift
@ViewBuilder
private func secondaryNotePane(note: Note, width: CGFloat, cornerRadius: CGFloat, primaryNote: Note) -> some View {
    let position = activeSplit?.position ?? .right
    let isLeftPane = (position == .left)

    NoteDetailView(
        note: note,
        editorInstanceID: splitEditorID,
        focusRequestID: splitFocusRequestID,
        contentTopInsetAdjustment: detailToggleToContentExtraSpacingWhenSidebarHidden
    ) { saveSplitNote($0) }
    .frame(width: width)
    .frame(maxHeight: .infinity)
    .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(detailBg))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(alignment: .bottomTrailing) {
        AIToolsOverlay(state: $splitAiToolsState).padding(.trailing, 18).padding(.bottom, 18)
    }
    .overlay(alignment: .bottomLeading) {
        NoteToolsBar(note: note, editorInstanceID: splitEditorID).padding(.leading, 18).padding(.bottom, 18)
    }
    .overlay(alignment: .topTrailing) {
        splitPaneControls(isLeftPane: isLeftPane, isPrimaryPane: false)
            .padding(.top, 12).padding(.trailing, 12)
    }
    .overlay {
        splitPickerOverlayView(for: .secondary, primaryNote: primaryNote)
    }
}
```

**Step 4: Delete old `secondaryPaneContent` function** (lines 568-597) — fully replaced.

**Step 5: Update `splitPaneResizeHandle`** (lines 599-634)

The drag gesture writes to `splitDragDelta` and on end updates `splitRatio`. Now it must update the active session's ratio:

In `.onEnded`, replace:
```swift
splitRatio = finalSecW / availableForSplit
```
with:
```swift
if let idx = activeSplitIndex {
    splitSessions[idx].ratio = finalSecW / availableForSplit
}
```

And replace `splitRatio` in the calculation with `activeSplit?.ratio ?? 0.5`.

Wait — `splitRatio` is read in `splitDetailLayout` which we already changed to read from `activeSplit?.ratio`. But `splitPaneResizeHandle` also reads `splitRatio` for the `.onEnded` calculation. Update the handle to also read from `activeSplit`:

```swift
let ratio = activeSplit?.ratio ?? 0.5
// ... use ratio instead of splitRatio in the .onEnded block
```

And in the `splitPosition` references inside the handle:
```swift
let position = activeSplit?.position ?? .right
let delta = position == .right ? -value.translation.width : value.translation.width
```

**Step 6: Build — may still have errors from other functions**

Continue to Task 5.

---

### Task 5: Migrate Split Action Functions

**Files:**
- Modify: `Jot/App/ContentView.swift` — `openSplit`, `closeSplit`, `closeLeftSplit`, `closeRightSplit`, `moveSplitToOtherSide`, `saveSplitNote`

**Step 1: Rewrite `openSplit` (line 1820)**

This is now only called from the `SplitOptionMenu` (initial split from sidebar icon). It creates a session with the primary note already set:

```swift
private func openSplit(position: SplitPosition) {
    var session = SplitSession()
    session.primaryNoteID = selectedNote?.id
    session.position = position
    splitSessions.append(session)
    activeSplitID = session.id
    pendingSplitID = session.id
    isSplitViewVisible = true
    withAnimation(.jotSpring) { isSplitMenuVisible = false }
    withAnimation(sidebarVisibilityAnimation) { isSidebarVisible = false }
}
```

**Step 2: Add `addNewSplit` — called from the "+" button (no preset direction)**

```swift
private func addNewSplit() {
    let session = SplitSession()
    splitSessions.append(session)
    activeSplitID = session.id
    pendingSplitID = session.id
    isSplitViewVisible = true
    withAnimation(sidebarVisibilityAnimation) { isSidebarVisible = false }
}
```

**Step 3: Add `cancelPendingSplit`**

```swift
private func cancelPendingSplit() {
    guard let pendingID = pendingSplitID else { return }
    withAnimation(.jotSpring) {
        splitSessions.removeAll(where: { $0.id == pendingID })
        pendingSplitID = nil
        // Fall back to most recent completed split, or single note
        if let lastCompleted = splitSessions.last(where: { $0.isComplete }) {
            activeSplitID = lastCompleted.id
        } else {
            activeSplitID = nil
            isSplitViewVisible = false
        }
    }
}
```

**Step 4: Rewrite `closeSplit` — now closes the active session**

```swift
private func closeSplit() {
    guard let activeID = activeSplitID else { return }
    withAnimation(.jotSpring) {
        splitSessions.removeAll(where: { $0.id == activeID })
        if activeID == pendingSplitID { pendingSplitID = nil }
        splitPickerOverlayPane = nil
        // Fall back
        if let next = splitSessions.last(where: { $0.isComplete }) {
            activeSplitID = next.id
        } else {
            activeSplitID = nil
            isSplitViewVisible = false
        }
    }
}
```

**Step 5: Rewrite `closeLeftSplit` and `closeRightSplit`**

These close the active session and optionally promote the surviving note:

```swift
private func closeLeftSplit() {
    guard let split = activeSplit else { return }
    let position = split.position
    if position == .left {
        // Left = secondary; closing secondary means just removing the split
        closeSplit()
    } else {
        // Left = primary; promote secondary to selectedNote
        if let secID = split.secondaryNoteID,
           let secNote = notesManager.notes.first(where: { $0.id == secID }) {
            selectedNote = secNote
            selectedNoteIDs = [secNote.id]
        }
        closeSplit()
    }
}

private func closeRightSplit() {
    guard let split = activeSplit else { return }
    let position = split.position
    if position == .right {
        // Right = secondary; closing secondary means just removing the split
        closeSplit()
    } else {
        // Right = primary; promote secondary to selectedNote
        if let secID = split.secondaryNoteID,
           let secNote = notesManager.notes.first(where: { $0.id == secID }) {
            selectedNote = secNote
            selectedNoteIDs = [secNote.id]
        }
        closeSplit()
    }
}
```

**Step 6: Rewrite `moveSplitToOtherSide` (line 1859)**

Swaps primary and secondary note IDs in the active session:

```swift
private func moveSplitToOtherSide() {
    guard let idx = activeSplitIndex else { return }
    let oldPrimary = splitSessions[idx].primaryNoteID
    let oldSecondary = splitSessions[idx].secondaryNoteID
    splitSessions[idx].primaryNoteID = oldSecondary
    splitSessions[idx].secondaryNoteID = oldPrimary
    // Update selectedNote to match new primary
    if let newPrimaryID = splitSessions[idx].primaryNoteID,
       let note = notesManager.notes.first(where: { $0.id == newPrimaryID }) {
        selectedNote = note
        selectedNoteIDs = [note.id]
    }
}
```

**Step 7: Rewrite `saveSplitNote` (line 1915)**

```swift
private func saveSplitNote(_ updated: Note) {
    notesManager.updateNote(updated)
    // No need to set splitNote — we look up by ID from splitSessions
}
```

**Step 8: Build to check remaining errors**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep "error:" | head -20`

Fix any remaining references to `splitNote`, `splitPrimaryNoteID`, `isSplitPicking`, `splitPosition`, `splitRatio`.

**Step 9: Commit**

```bash
git add Jot/App/ContentView.swift
git commit -m "feat: migrate all split action functions to SplitSession array"
```

---

### Task 6: Update SplitNotePickerView for Multi-Split

**Files:**
- Modify: `Jot/Views/Components/SplitNotePickerView.swift`

**Step 1: Add `showCloseButton` parameter**

The "Close splitview" button should only show during the initial single-split creation flow (from the sidebar split icon), not during multi-split "+" creation where both panes show pickers.

```swift
struct SplitNotePickerView: View {
    let recentNotes: [Note]
    let onSelect: (Note) -> Void
    let onClose: () -> Void
    var showCloseButton: Bool = true  // default true for backward compat
    // ... rest unchanged
```

Wrap the `.overlay(alignment: .bottom)` block:
```swift
if showCloseButton {
    // existing close button overlay
}
```

**Step 2: Update call sites**

In `splitPickerPane` (new function from Task 4), pass `showCloseButton: false`. The existing `secondaryPaneContent` call site is deleted, so no other changes needed.

Actually — `secondaryPaneContent` is deleted. The `splitPickerPane` in Task 4 already calls `SplitNotePickerView`. Update that call to pass `showCloseButton: false`:

```swift
SplitNotePickerView(
    recentNotes: recentNotes(excluding: excludeNote),
    onSelect: { note in ... },
    onClose: { cancelPendingSplit() },
    showCloseButton: false
)
```

Wait — for the "+" flow, BOTH panes are pickers. Neither should have "Close splitview". But from the original `openSplit` flow (sidebar split icon), the primary note is pre-set, only the secondary pane shows a picker with the close button. So `showCloseButton` should be `true` only when the split was created from the sidebar icon AND this is the secondary pane.

Simpler approach: pass `showCloseButton: pendingSplitID == nil` — false during pending creation (both panes are pickers), true when only one pane is picking (single-split upgrade flow). Actually even simpler: if `pendingSplitID != nil`, no close button on any picker.

In `splitPickerPane`:
```swift
showCloseButton: false
```

For the original `openSplit` flow — wait, the original flow now also uses `splitPickerPane` for the secondary. The primary is already set via `openSplit`. The secondary picker pane should have the close button since there's a single existing split being created. So:

```swift
showCloseButton: !isPrimary && activeSplit?.primaryNoteID != nil
```

This means: show close button only on the secondary picker when the primary is already chosen (original flow). Never on the primary picker (multi-split "+" flow creates both as pickers).

**Step 3: Build and verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`

**Step 4: Commit**

```bash
git add Jot/Views/Components/SplitNotePickerView.swift Jot/App/ContentView.swift
git commit -m "feat: add showCloseButton param to SplitNotePickerView"
```

---

### Task 7: Update `splitPickerOverlayView` and Remaining References

**Files:**
- Modify: `Jot/App/ContentView.swift` — overlay view, handleNoteTap, layout switch

**Step 1: Update `splitPickerOverlayView` (line 1787)**

Replace references to `splitNote` and `splitPrimaryNoteID`:

```swift
@ViewBuilder
private func splitPickerOverlayView(for pane: SplitPickerPane, primaryNote: Note) -> some View {
    if splitPickerOverlayPane == pane {
        ZStack {
            Color.black.opacity(0.05)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.jotSpring) { splitPickerOverlayPane = nil }
                }

            SplitPickerOverlayCard(
                notes: recentNotes(excluding: pane == .primary ? (activeSecondaryNote ?? primaryNote) : primaryNote),
                onSelect: { note in
                    withAnimation(.jotSpring) {
                        guard let idx = activeSplitIndex else { return }
                        if pane == .primary {
                            splitSessions[idx].primaryNoteID = note.id
                            selectedNote = note
                            selectedNoteIDs = [note.id]
                        } else {
                            splitSessions[idx].secondaryNoteID = note.id
                        }
                        splitPickerOverlayPane = nil
                    }
                }
            )
        }
    }
}
```

**Step 2: Update the main layout switch (line 468)**

The `if shouldShowSplitLayout` block passes `primaryNote`. Now `primaryNote` comes from the active session:

```swift
if shouldShowSplitLayout, let primaryNote = activePrimaryNote {
    splitDetailLayout(primaryNote: primaryNote, totalWidth: totalDetailWidth, cornerRadius: cornerRadius)
} else if shouldShowSplitLayout, activeSplit != nil {
    // Pending split with no primary yet — still show split layout with both pickers
    // Pass a dummy note; splitDetailLayout handles nil primaryNoteID
    splitDetailLayout(primaryNote: selectedNote ?? Note(title: "", content: ""), totalWidth: totalDetailWidth, cornerRadius: cornerRadius)
} else {
    singleNotePane(note: note, width: totalDetailWidth, cornerRadius: cornerRadius)
}
```

Actually this needs care. When both notes are nil (fresh "+" click), `splitDetailLayout` renders two picker panes. The `primaryNote` parameter is used by `singleNotePane` for the primary side, but if both are pickers, we never call `singleNotePane`. So we can pass a placeholder:

```swift
if shouldShowSplitLayout {
    let primaryNote = activePrimaryNote ?? selectedNote ?? Note(title: "", content: "")
    splitDetailLayout(primaryNote: primaryNote, totalWidth: totalDetailWidth, cornerRadius: cornerRadius)
} else {
    singleNotePane(note: note, width: totalDetailWidth, cornerRadius: cornerRadius)
}
```

**Step 3: Update `handleNoteTap` (line 1869)**

Replace `isSplitActive`:

```swift
case .plain:
    if isSplitActive { isSplitViewVisible = false }
    openNote(note)
```

`isSplitActive` is already updated to `!splitSessions.isEmpty`. No change needed here.

**Step 4: Fix `splitMenuIconButton` (line 1627)**

Currently uses `!isSplitActive`. Still correct with new definition. No change needed.

**Step 5: Grep for any remaining `splitNote`, `splitPrimaryNoteID`, `isSplitPicking`, old `splitPosition`, old `splitRatio` references**

Run: `grep -n "splitNote\|splitPrimaryNoteID\|isSplitPicking" Jot/App/ContentView.swift`

Fix all remaining references. Common patterns:
- `splitNote = note` → `splitSessions[idx].secondaryNoteID = note.id`
- `splitNote != nil` → `activeSplit?.secondaryNoteID != nil`
- `isSplitPicking` → `isActiveSplitPending`

**Step 6: Build and fix**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | grep "error:" | head -20`

Iterate until zero errors.

**Step 7: Commit**

```bash
git add Jot/App/ContentView.swift
git commit -m "feat: update overlay, layout switch, and fix all remaining split references"
```

---

### Task 8: Sidebar — Multi-Split Containers + Add Button

**Files:**
- Modify: `Jot/App/ContentView.swift` — `activeSplitSidebarSection`, new `addSplitButton`, sidebar placement

**Step 1: Rewrite `activeSplitSidebarSection`**

Iterate over all completed sessions, render a container per session. Show header once:

```swift
@ViewBuilder
private var activeSplitSidebarSection: some View {
    let completedSessions = splitSessions.filter { $0.isComplete }
    if !splitSessions.isEmpty {
        VStack(spacing: 0) {
            // Header
            Text("Active Split")
                .font(FontManager.heading(size: 13, weight: .medium))
                .foregroundColor(Color("SecondaryTextColor"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .padding(.bottom, 4)

            // Completed split containers
            VStack(spacing: 8) {
                ForEach(completedSessions) { session in
                    splitSessionContainer(session: session)
                }
            }

            // Add button (4px below last container)
            addSplitButton
                .padding(.top, completedSessions.isEmpty ? 0 : 4)
        }
    }
}
```

**Step 2: Extract `splitSessionContainer`**

```swift
private func splitSessionContainer(session: SplitSession) -> some View {
    let pNote = notesManager.notes.first(where: { $0.id == session.primaryNoteID })
    let sNote = notesManager.notes.first(where: { $0.id == session.secondaryNoteID })

    return VStack(spacing: 4) {
        if let pNote {
            splitSessionNoteRow(note: pNote, session: session)
        }

        Image("WavyDividerLine")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color("IconSecondaryColor"))
            .frame(height: 4)
            .padding(.horizontal, 8)
            .opacity(0.4)

        if let sNote {
            splitSessionNoteRow(note: sNote, session: session)
        }
    }
    .padding(4)
    .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colorScheme == .light ? Color.white : Color(red: 0.047, green: 0.039, blue: 0.035))
    )
    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 0)
}
```

**Step 3: Add `splitSessionNoteRow` (replaces `activeSplitNoteRow`)**

```swift
private func splitSessionNoteRow(note: Note, session: SplitSession) -> some View {
    Button {
        activeSplitID = session.id
        isSplitViewVisible = true
        if let primaryID = session.primaryNoteID,
           let pNote = notesManager.notes.first(where: { $0.id == primaryID }) {
            selectedNote = pNote
            selectedNoteIDs = [pNote.id]
        }
    } label: {
        HStack {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.5)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            Text(formatSplitDate(note.date))
                .font(FontManager.metadata(size: 11, weight: .medium))
                .tracking(-0.2)
                .foregroundColor(Color("SecondaryTextColor"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .macPointingHandCursor()
}
```

**Step 4: Add `addSplitButton`**

```swift
private var addSplitButton: some View {
    Button {
        if pendingSplitID != nil {
            cancelPendingSplit()
        } else {
            withAnimation(.jotSpring) { addNewSplit() }
        }
    } label: {
        HStack {
            Spacer()
            if pendingSplitID != nil {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .tracking(-0.3)
            } else {
                Image("IconPlusSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color("SecondaryTextColor"))
                    .frame(width: 18, height: 18)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
    .buttonStyle(.plain)
    .macPointingHandCursor()
    .padding(4)
    .overlay(
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            .foregroundColor(Color("BorderColor"))
    )
    .subtleHoverScale(1.02)
}
```

Note: `"BorderColor"` should map to `#d6d3d1` in light mode. Check if this color set exists. If not, use `Color(red: 0.84, green: 0.83, blue: 0.82)` directly or create the color set.

**Step 5: Delete old `activeSplitNoteRow` function**

It's replaced by `splitSessionNoteRow`.

**Step 6: Build and verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`

**Step 7: Commit**

```bash
git add Jot/App/ContentView.swift
git commit -m "feat: multi-split sidebar containers with add/cancel button"
```

---

### Task 9: Ensure Border Color Asset Exists

**Files:**
- Check: `Jot/Assets.xcassets/BorderColor.colorset/` — may or may not exist

**Step 1: Check**

Run: `ls Jot/Assets.xcassets/ | grep -i border`

If `BorderColor.colorset` doesn't exist, create it:

Light: `#d6d3d1` (R: 0.839, G: 0.827, B: 0.820)
Dark: appropriate dark variant (e.g., `#44403c` or `rgba(255,255,255,0.15)`)

Or — simpler — just use an inline color in the dashed border views and skip creating a color set. The Figma specifies `#d6d3d1` for light. For dark mode, use `Color.primary.opacity(0.2)`.

**Step 2: Build and verify**

**Step 3: Commit if asset created**

---

### Task 10: Final Cleanup and Integration Test

**Files:**
- Modify: `Jot/App/ContentView.swift` — any remaining fixes

**Step 1: Delete dead code**

- Remove old `splitPrimaryNote` computed property (replaced by `activePrimaryNote`)
- Remove old `secondaryPaneContent` function (replaced by `secondaryNotePane` + `splitPickerPane`)
- Remove old `activeSplitNoteRow` function (replaced by `splitSessionNoteRow`)
- Remove `@State private var splitNote` if not yet removed
- Remove `@State private var isSplitPicking` if not yet removed
- Remove `SplitOptionMenu.swift` usage for active-mode branch if any remains

**Step 2: Verify no stale references**

Run: `grep -n "splitNote\b\|splitPrimaryNoteID\|isSplitPicking\|splitPrimaryNote\b" Jot/App/ContentView.swift`

Should return zero matches.

**Step 3: Full build**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 4: Launch and manual test**

```bash
pkill -x Jot 2>/dev/null
touch ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
killall iconservicesagent 2>/dev/null || true
sleep 1 && open ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
```

Verify:
1. Sidebar split icon opens direction menu, creates split with primary pre-set
2. "+" button appears below Active Split section
3. Clicking "+" creates two dashed-border picker panes (no fill, transparent)
4. Selecting notes in both panes completes the split
5. "+" becomes "Cancel" during creation, canceling removes the pending split
6. Multiple completed splits show as separate containers in sidebar (8px gap between)
7. Clicking a sidebar container switches to that split
8. Clicking a regular note hides split, shows single note
9. Per-pane controls (flashcards, move, close) work on each split independently
10. Closing a split removes its sidebar container and falls back correctly

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: complete multi-split system with unlimited independent split sessions"
```
