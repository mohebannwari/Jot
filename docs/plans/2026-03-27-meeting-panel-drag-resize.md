# Meeting Notes Panel: Drag-to-Reorder + Resize

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the MeetingNoteDetailPanel draggable to any position within the note detail content, and resizable (both width and height) with a minimum width of 400pt.

**Architecture:** The panel stays as a SwiftUI view in NoteDetailView's VStack. A `MeetingPanelSlot` enum controls its position among content sections. Resize uses SwiftUI `DragGesture` on right-edge and bottom-edge handles. Position, width ratio, and height are persisted on the Note model via NoteEntity scalar columns.

**Tech Stack:** SwiftUI, SwiftData, DragGesture, NSCursor

---

## Context

### Current State
- `MeetingNoteDetailPanel` is a SwiftUI view at a fixed position in `NoteDetailView.editorScrollContent` VStack (line 314)
- VStack order: date > title > backlinks > **meeting panel** > AI summary > AI key points > AI top panel > editor > spacer
- Panel has `maxContentHeight: CGFloat = 300` (fixed)
- No drag/reorder logic exists anywhere in NoteDetailView
- Existing resizable blocks (code blocks, callouts) are NSView overlays inside NSTextView -- different pattern; not applicable here since the meeting panel is SwiftUI

### Key Files
- `Jot/Views/Components/MeetingNoteDetailPanel.swift` (308 lines) -- the panel
- `Jot/Views/Screens/NoteDetailView.swift` (~5400 lines) -- hosts the panel at line 314
- `Jot/Models/Note.swift` -- Note struct, needs new fields
- `Jot/Models/SwiftData/NoteEntity.swift` -- persistence, needs new columns
- `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` -- round-trip conversion

### Design Decisions
- **Position is slot-based**, not free-form pixel offset. Slots: `.aboveAIPanels` (default/current), `.belowAIPanels`, `.belowEditor`. This keeps layout predictable and avoids floating-point drift.
- **Width stored as ratio** of container width (like image `widthRatio`), not absolute pixels. This adapts to window resizing.
- **Height stored as absolute CGFloat** (like tabs `containerHeight`). Content height doesn't scale with container width.
- **Min width: 400pt** (matching code blocks and callouts). Effective min = `min(400, containerWidth)`.
- **Min height: 120pt** (enough for collapsed header + one tab row). No max -- user decides.
- **Drag affordance:** 6-dot grip icon in the accordion header, visible on hover. The entire header is the drag surface.
- **Drop zones:** Thin horizontal lines that appear between sections during drag, showing valid placement targets.

---

### Task 1: Add Persistence Fields

**Files:**
- Modify: `Jot/Models/Note.swift`
- Modify: `Jot/Models/SwiftData/NoteEntity.swift`

**Step 1: Add fields to Note struct**

In `Jot/Models/Note.swift`, add after the existing meeting fields:

```swift
// Meeting Panel Layout
var meetingPanelSlot: Int = 0          // 0 = aboveAIPanels, 1 = belowAIPanels, 2 = belowEditor
var meetingPanelWidthRatio: Double = 1.0  // 0.0...1.0 ratio of container width
var meetingPanelHeight: Double = 300      // absolute height in points
```

Use `Int` for the slot (not an enum) to keep `Codable` simple and avoid migration headaches. The enum lives in the view layer.

**Step 2: Add columns to NoteEntity**

In `Jot/Models/SwiftData/NoteEntity.swift`, add three persisted properties:

```swift
var meetingPanelSlot: Int = 0
var meetingPanelWidthRatio: Double = 1.0
var meetingPanelHeight: Double = 300
```

**Step 3: Update round-trip conversion**

In `NoteEntity.init(from note:)`, add:
```swift
self.meetingPanelSlot = note.meetingPanelSlot
self.meetingPanelWidthRatio = note.meetingPanelWidthRatio
self.meetingPanelHeight = note.meetingPanelHeight
```

In `NoteEntity.toNote()`, add:
```swift
note.meetingPanelSlot = self.meetingPanelSlot
note.meetingPanelWidthRatio = self.meetingPanelWidthRatio
note.meetingPanelHeight = self.meetingPanelHeight
```

**Step 4: Build to verify no errors**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Jot/Models/Note.swift Jot/Models/SwiftData/NoteEntity.swift
git commit -m "feat: add meeting panel layout persistence fields (slot, widthRatio, height)"
```

---

### Task 2: Add Resize Handles to MeetingNoteDetailPanel

**Files:**
- Modify: `Jot/Views/Components/MeetingNoteDetailPanel.swift`

This task adds right-edge and bottom-edge resize handles to the panel using SwiftUI `DragGesture`. The handles are invisible strips that change the cursor on hover and track drag delta to resize.

**Step 1: Add width/height bindings and constants**

Replace the existing property interface and add resize state. The panel needs to accept bindings for width and height (so the parent can persist changes), plus the container width for ratio calculations.

Add to `MeetingNoteDetailPanel`:

```swift
// Layout bindings (from parent)
@Binding var panelHeight: CGFloat
@Binding var panelWidthRatio: CGFloat
var containerWidth: CGFloat

// Resize state
@State private var isDraggingRight = false
@State private var isDraggingBottom = false
@State private var dragStartWidth: CGFloat = 0
@State private var dragStartHeight: CGFloat = 0

// Constants
static let minWidth: CGFloat = 400
static let minHeight: CGFloat = 120
```

Remove the old `maxContentHeight` constant (line 26). Replace it with `panelHeight`.

**Step 2: Add resize handle views**

Add two private views for the edge handles:

```swift
// MARK: - Resize Handles

private var rightResizeHandle: some View {
    Color.clear
        .frame(width: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.compatFrameResize(position: "right").push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDraggingRight {
                        isDraggingRight = true
                        dragStartWidth = panelWidthRatio * containerWidth
                    }
                    let newWidth = dragStartWidth + value.translation.width
                    let effectiveMin = min(Self.minWidth, containerWidth)
                    let clamped = max(effectiveMin, min(containerWidth, newWidth))
                    panelWidthRatio = clamped / containerWidth
                }
                .onEnded { _ in
                    isDraggingRight = false
                }
        )
}

private var bottomResizeHandle: some View {
    Color.clear
        .frame(height: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.compatFrameResize(position: "bottom").push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDraggingBottom {
                        isDraggingBottom = true
                        dragStartHeight = panelHeight
                    }
                    let newHeight = dragStartHeight + value.translation.height
                    panelHeight = max(Self.minHeight, newHeight)
                }
                .onEnded { _ in
                    isDraggingBottom = false
                }
        )
}
```

Note: `NSCursor.compatFrameResize(position:)` is an existing extension in this codebase (used by code block and tabs container resize handles). If it doesn't exist as a static method, check `TodoEditorRepresentable.swift` for the exact signature and use it.

**Step 3: Update body to apply width, height, and attach handles**

Replace the `body` computed property:

```swift
var body: some View {
    let effectiveWidth = max(
        min(Self.minWidth, containerWidth),
        min(containerWidth, panelWidthRatio * containerWidth)
    )

    HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
            accordionHeader
            if isExpanded {
                tabBar
                tabContent
            }
        }
        .frame(width: effectiveWidth - 12) // leave room for resize handle

        if isExpanded {
            rightResizeHandle
        }
    }
    .frame(width: effectiveWidth, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            .fill(panelBackground)
    )
    .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
    .overlay(alignment: .bottom) {
        if isExpanded {
            bottomResizeHandle
                .offset(y: 6) // straddle the bottom edge
        }
    }
}
```

**Step 4: Update ThinScrollView to use panelHeight**

In `tabContent`, replace the hardcoded `maxContentHeight` reference:

```swift
ThinScrollView(maxHeight: isExpanded ? panelHeight - 80 : 0) {
    // ... existing content unchanged
}
```

The `- 80` accounts for the accordion header (~48pt) and tab bar (~32pt). Adjust if needed after visual testing.

**Step 5: Build to verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (will fail until Task 3 updates the call site)

**Step 6: Commit**

```bash
git add Jot/Views/Components/MeetingNoteDetailPanel.swift
git commit -m "feat: add right-edge and bottom-edge resize handles to meeting panel"
```

---

### Task 3: Add Drag-to-Reorder in NoteDetailView

**Files:**
- Modify: `Jot/Views/Screens/NoteDetailView.swift`

This task adds the slot-based positioning system and drag-to-reorder gesture.

**Step 1: Define the slot enum and add state**

Add near the top of `NoteDetailView` (with the other meeting-related state):

```swift
enum MeetingPanelSlot: Int, CaseIterable {
    case aboveAIPanels = 0   // current default position
    case belowAIPanels = 1
    case belowEditor = 2
}

@State private var meetingPanelSlot: MeetingPanelSlot = .aboveAIPanels
@State private var meetingPanelWidthRatio: CGFloat = 1.0
@State private var meetingPanelHeight: CGFloat = 300
@State private var isDraggingMeetingPanel = false
@State private var meetingPanelDragOffset: CGFloat = 0
```

Initialize from note in `init` or `.onAppear`:
```swift
meetingPanelSlot = MeetingPanelSlot(rawValue: note.meetingPanelSlot) ?? .aboveAIPanels
meetingPanelWidthRatio = CGFloat(note.meetingPanelWidthRatio)
meetingPanelHeight = CGFloat(note.meetingPanelHeight)
```

**Step 2: Extract the meeting panel into a reusable computed property**

Create a computed property that builds the panel with all its bindings:

```swift
@ViewBuilder
private var meetingNotePanel: some View {
    if savedIsMeetingNote && !savedMeetingSummary.isEmpty {
        MeetingNoteDetailPanel(
            meetingSummary: savedMeetingSummary,
            meetingTranscript: savedMeetingTranscript,
            meetingManualNotes: $savedMeetingManualNotes,
            meetingDuration: savedMeetingDuration,
            meetingLanguage: savedMeetingLanguage,
            meetingDate: note.date,
            onNotesChanged: { newNotes in
                var updated = note
                updated.meetingTranscript = savedMeetingTranscript
                updated.meetingSummary = savedMeetingSummary
                updated.meetingDuration = savedMeetingDuration
                updated.meetingLanguage = savedMeetingLanguage
                updated.meetingManualNotes = newNotes
                updated.isMeetingNote = true
                notesManager.updateNote(updated)
            },
            panelHeight: $meetingPanelHeight,
            panelWidthRatio: $meetingPanelWidthRatio,
            containerWidth: containerWidth  // from GeometryReader or existing source
        )
        .offset(y: isDraggingMeetingPanel ? meetingPanelDragOffset : 0)
        .zIndex(isDraggingMeetingPanel ? 100 : 0)
        .shadow(
            color: isDraggingMeetingPanel ? .black.opacity(0.15) : .clear,
            radius: isDraggingMeetingPanel ? 12 : 0,
            y: isDraggingMeetingPanel ? 4 : 0
        )
        .scaleEffect(isDraggingMeetingPanel ? 1.02 : 1.0)
        .animation(.jotSmoothFast, value: isDraggingMeetingPanel)
        .transition(.opacity.combined(with: .offset(y: -8)))
    }
}
```

**Step 3: Restructure the VStack to use slot-based positioning**

In `editorScrollContent`, replace the fixed panel placement with conditional slots. Remove the existing `MeetingNoteDetailPanel` block (lines 314-335) and place the panel at the correct slot:

```swift
VStack(alignment: .leading, spacing: 8) {
    // Date row (unchanged)
    // Title (unchanged)

    // Backlinks (unchanged)
    if !backlinks.isEmpty {
        backlinksSection.padding(.top, 4)
    }

    // SLOT 0: aboveAIPanels (default)
    if meetingPanelSlot == .aboveAIPanels {
        meetingNotePanel
    }

    // AI panels (unchanged)
    if let summaryText = aiSummaryText { ... }
    if let keyPointsItems = aiKeyPointsItems { ... }
    if shouldShowTopPanel { ... }

    // SLOT 1: belowAIPanels
    if meetingPanelSlot == .belowAIPanels {
        meetingNotePanel
    }

    // Editor (unchanged)
    TodoRichTextEditor(...)

    // SLOT 2: belowEditor
    if meetingPanelSlot == .belowEditor {
        meetingNotePanel
    }

    // Command menu spacer (unchanged)
}
```

**Step 4: Add the drag gesture to MeetingNoteDetailPanel's accordion header**

In `MeetingNoteDetailPanel.swift`, add a drag handle icon and gesture to the accordion header. Add a 6-dot grip icon that appears on hover:

```swift
// In accordionHeader, add before the Spacer():
@State private var isHeaderHovered = false
var onDragChanged: ((DragGesture.Value) -> Void)? = nil
var onDragEnded: ((DragGesture.Value) -> Void)? = nil
```

In the header HStack, after the language text and before `Spacer()`:

```swift
// Drag grip (visible on hover)
if isHeaderHovered {
    Image(systemName: "line.3.horizontal")
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(Color("TertiaryTextColor"))
        .transition(.opacity)
}
```

Add `.onHover` and a simultaneous drag gesture to the header:

```swift
.onHover { isHeaderHovered = $0 }
.simultaneousGesture(
    DragGesture(minimumDistance: 8)
        .onChanged { value in
            onDragChanged?(value)
        }
        .onEnded { value in
            onDragEnded?(value)
        }
)
```

**Step 5: Implement drag logic in NoteDetailView**

Wire up the drag callbacks on the panel. In the `meetingNotePanel` computed property, add the drag handlers:

```swift
MeetingNoteDetailPanel(
    // ... existing params ...,
    onDragChanged: { value in
        isDraggingMeetingPanel = true
        meetingPanelDragOffset = value.translation.height
    },
    onDragEnded: { value in
        let dy = value.translation.height
        withAnimation(.jotSmoothFast) {
            isDraggingMeetingPanel = false
            meetingPanelDragOffset = 0

            // Determine new slot based on drag direction and distance
            let threshold: CGFloat = 60
            if dy > threshold {
                // Dragged down -- move to next slot
                switch meetingPanelSlot {
                case .aboveAIPanels: meetingPanelSlot = .belowAIPanels
                case .belowAIPanels: meetingPanelSlot = .belowEditor
                case .belowEditor: break // already at bottom
                }
            } else if dy < -threshold {
                // Dragged up -- move to previous slot
                switch meetingPanelSlot {
                case .aboveAIPanels: break // already at top
                case .belowAIPanels: meetingPanelSlot = .aboveAIPanels
                case .belowEditor: meetingPanelSlot = .belowAIPanels
                }
            }
        }
        // Persist
        persistMeetingPanelLayout()
    }
)
```

**Step 6: Add drop zone indicators**

During drag, show thin colored lines at each available slot. Add an overlay or inline views:

```swift
@ViewBuilder
private var dropZoneIndicator: some View {
    RoundedRectangle(cornerRadius: 2)
        .fill(Color.accentColor.opacity(0.5))
        .frame(height: 3)
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .center)))
}
```

In the VStack, at each slot that is NOT the current slot, show the indicator when `isDraggingMeetingPanel`:

```swift
// Before each slot position:
if isDraggingMeetingPanel && meetingPanelSlot != .aboveAIPanels {
    dropZoneIndicator
}
```

(Repeat for each slot.)

**Step 7: Build to verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add Jot/Views/Components/MeetingNoteDetailPanel.swift Jot/Views/Screens/NoteDetailView.swift
git commit -m "feat: drag-to-reorder meeting panel between content slots"
```

---

### Task 4: Persist Layout Changes

**Files:**
- Modify: `Jot/Views/Screens/NoteDetailView.swift`

**Step 1: Add persistence helper**

```swift
private func persistMeetingPanelLayout() {
    var updated = note
    updated.meetingPanelSlot = meetingPanelSlot.rawValue
    updated.meetingPanelWidthRatio = Double(meetingPanelWidthRatio)
    updated.meetingPanelHeight = Double(meetingPanelHeight)
    updated.isMeetingNote = true
    updated.meetingSummary = savedMeetingSummary
    updated.meetingTranscript = savedMeetingTranscript
    updated.meetingDuration = savedMeetingDuration
    updated.meetingLanguage = savedMeetingLanguage
    updated.meetingManualNotes = savedMeetingManualNotes
    notesManager.updateNote(updated)
}
```

**Step 2: Call persist on resize end**

Add `.onChange` modifiers for the resize bindings (debounced to avoid saving on every pixel):

```swift
.onChange(of: meetingPanelWidthRatio) { _, _ in
    persistMeetingPanelLayout()
}
.onChange(of: meetingPanelHeight) { _, _ in
    persistMeetingPanelLayout()
}
```

Alternatively, persist only on drag end by adding an `onResizeEnded` callback to MeetingNoteDetailPanel (cleaner, avoids saving mid-drag). The drag gesture `.onEnded` already calls persist for position. Add similar `.onEnded` calls in the resize handle gestures.

**Step 3: Load persisted values on note change**

In the `.onAppear` or `.onChange(of: note)` handler where meeting fields are loaded:

```swift
meetingPanelSlot = MeetingPanelSlot(rawValue: note.meetingPanelSlot) ?? .aboveAIPanels
meetingPanelWidthRatio = CGFloat(note.meetingPanelWidthRatio)
meetingPanelHeight = CGFloat(note.meetingPanelHeight)
```

**Step 4: Build and verify full round-trip**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Jot/Views/Screens/NoteDetailView.swift
git commit -m "feat: persist meeting panel position, width ratio, and height"
```

---

## Edge Cases to Handle

- **Container width is less than 400:** Effective min = containerWidth. Panel fills available space.
- **Panel not expanded (collapsed):** Resize handles should NOT appear when collapsed. Only the header is visible.
- **Window resize:** Width ratio recalculates on the fly. Height stays absolute.
- **New meeting notes:** Default to slot 0, widthRatio 1.0, height 300.
- **Non-meeting notes:** All panel layout state is ignored (panel doesn't render).

## Visual Reference

The drag handle (6-dot grip or `line.3.horizontal` SF Symbol) appears on hover in the accordion header, left of the chevron. During drag, the panel lifts slightly (scale 1.02) with a soft shadow. Drop zone indicators (3pt accent-colored bars) appear at valid slots.

Resize handles are invisible 12pt strips on the right edge and bottom edge. Cursor changes to resize arrow on hover. The panel corner radius is preserved during resize via `.clipShape`.
