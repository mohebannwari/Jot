# Product Requirements Prompt: Batch 2 -- Spotlight Integration + Printing

## Metadata
- **Created**: 2026-03-20
- **Target OS**: macOS 26+
- **Confidence**: 9/10
- **Estimated Complexity**: Medium
- **Linear Issues**: DES-267, DES-268
- **Branch**: `feature/batch-2-spotlight-printing`

---

## 1. Feature Overview

### Purpose
Make Jot a first-class macOS citizen by integrating with two core platform features: Spotlight search (notes findable system-wide) and native printing (Cmd+P). These are independent features that share no code but both deepen OS integration.

### Key Requirements
- Notes indexed in Spotlight with title, content preview, and tags
- Clicking a Spotlight result opens Jot to that note
- Locked notes indexed by title only
- Deleted/archived notes removed from index
- Cmd+P opens native print dialog for the current note
- Printed output preserves rich text formatting

---

## 2. Context & Background

### Existing Architecture

**Note lifecycle hooks in `SimpleSwiftDataManager`:**
- `addNote()` (line 316) -- creates note, inserts into SwiftData, appends to `notes` array
- `updateNote()` (line 344) -- updates entity and local array
- `moveToTrash()` (line 501) -- sets `isDeleted=true`, `deletedDate=Date()`
- `restoreFromTrash()` (line 535) -- reverses trash
- `archiveNotes()` (line 420) -- sets `isArchived=true`
- `unarchiveNotes()` (line 451) -- reverses archive

**Markup stripping already exists:**
- `NoteExportService.convertMarkupToPlainText()` at line 461 strips all `[[...]]` tags
- Returns clean text suitable for Spotlight indexing

**Editor architecture (for printing):**
- `TodoEditorRepresentable` (NSViewRepresentable) manages `InlineNSTextView`
- Coordinator stores `private weak var textView: NSTextView?` (line 1151)
- All editor actions use NotificationCenter with `editorInstanceID` filtering
- Pattern: register observer in `configure(with:)`, filter by `editorInstanceID`, dispatch on `@MainActor`

**No existing deep linking:**
- No `NSApplicationDelegateAdaptor` in JotApp.swift
- No `onContinueUserActivity` handling
- No URL scheme in Info.plist

### Dependencies
**Spotlight:**
- CoreSpotlight framework (`CSSearchableIndex`, `CSSearchableItem`, `CSSearchableItemAttributeSet`)
- `NoteExportService` for `convertMarkupToPlainText()`

**Printing:**
- AppKit `NSPrintOperation`, `NSPrintInfo`
- Access to Coordinator's NSTextView reference

---

## 3. Architecture & Design Patterns

### File Structure
```
Jot/
├── App/
│   ├── JotApp.swift                    # MODIFY -- add AppDelegate adaptor
│   ├── AppDelegate.swift               # CREATE -- handle Spotlight deep links
│   └── PrintCommands.swift             # CREATE -- Cmd+P menu command
├── Utils/
│   └── SpotlightIndexer.swift          # CREATE -- CoreSpotlight wrapper
└── Views/
    └── Components/
        └── TodoEditorRepresentable.swift  # MODIFY -- print notification handler
```

### SpotlightIndexer Pattern
```swift
import CoreSpotlight

@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    private let index = CSSearchableIndex.default()
    private let domainID = "com.jot.notes"
    private let exportService = NoteExportService()

    func indexNote(_ note: Note) {
        guard !note.isDeleted, !note.isArchived else {
            deindexNotes(ids: [note.id])
            return
        }
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = note.title.isEmpty ? "Untitled" : note.title
        attrs.contentDescription = note.isLocked ? nil : exportService.convertMarkupToPlainText(note.content)
        attrs.keywords = note.tags
        attrs.lastUsedDate = note.date
        attrs.contentCreationDate = note.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attrs
        )
        index.indexSearchableItems([item])
    }

    func deindexNotes(ids: Set<UUID>) {
        index.deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    func reindexAll(_ notes: [Note]) {
        let items = notes
            .filter { !$0.isDeleted && !$0.isArchived }
            .map { note -> CSSearchableItem in
                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = note.title.isEmpty ? "Untitled" : note.title
                attrs.contentDescription = note.isLocked ? nil : exportService.convertMarkupToPlainText(note.content)
                attrs.keywords = note.tags
                attrs.lastUsedDate = note.date
                attrs.contentCreationDate = note.createdAt
                return CSSearchableItem(
                    uniqueIdentifier: note.id.uuidString,
                    domainIdentifier: domainID,
                    attributeSet: attrs
                )
            }
        index.deleteAllSearchableItems { [weak self] _ in
            self?.index.indexSearchableItems(items)
        }
    }
}
```

### Print Notification Pattern (matches existing editor patterns)
```swift
// In Coordinator.configure(with:), following the exact pattern from line 1911-1919:
let printNote = NotificationCenter.default.addObserver(
    forName: .printCurrentNote, object: nil, queue: .main
) { [weak self] notification in
    if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
       let myID = self?.editorInstanceID, nid != myID { return }
    Task { @MainActor [weak self] in
        self?.handlePrint()
    }
}
observers.append(printNote)
```

---

## 4. Implementation Steps

### Step 1: Create SpotlightIndexer
**Objective:** Build the CoreSpotlight indexing wrapper.

**Files to Create:**
- `Jot/Utils/SpotlightIndexer.swift`

**Implementation:**
- Singleton `@MainActor` class
- `indexNote(_ note: Note)` -- index or deindex based on state
- `deindexNotes(ids: Set<UUID>)` -- remove from index
- `reindexAll(_ notes: [Note])` -- full reindex on app launch
- Uses `NoteExportService().convertMarkupToPlainText()` for content
- Locked notes: index title only (contentDescription = nil)

**Validation:**
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

---

### Step 2: Hook SpotlightIndexer into SimpleSwiftDataManager
**Objective:** Call indexer after every note lifecycle event.

**Files to Modify:**
- `Jot/Models/SwiftData/SimpleSwiftDataManager.swift`

**Hooks to add:**
- After `addNote()` returns (line ~336): `SpotlightIndexer.shared.indexNote(note)`
- After `updateNote()` saves (line ~395): `SpotlightIndexer.shared.indexNote(updatedNote)`
- After `moveToTrash()` completes (line ~530): `SpotlightIndexer.shared.deindexNotes(ids: ids)`
- After `restoreFromTrash()` completes: re-index restored notes
- After `archiveNotes()`: `SpotlightIndexer.shared.deindexNotes(ids: ids)`
- After `unarchiveNotes()`: re-index unarchived notes
- After `permanentlyDeleteNotes()`: `SpotlightIndexer.shared.deindexNotes(ids: ids)`

**On app launch:** Call `SpotlightIndexer.shared.reindexAll(notesManager.notes)` after initial load.

---

### Step 3: Create AppDelegate for Spotlight Deep Links
**Objective:** Handle `CSSearchableItemActionType` to navigate to a note.

**Files to Create:**
- `Jot/App/AppDelegate.swift`

**Files to Modify:**
- `Jot/App/JotApp.swift` -- add `@NSApplicationDelegateAdaptor`

**Implementation:**
```swift
import Cocoa
import CoreSpotlight

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let noteIDString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let noteID = UUID(uuidString: noteIDString) else {
            return false
        }
        NotificationCenter.default.post(
            name: .openNoteFromSpotlight,
            object: nil,
            userInfo: ["noteID": noteID]
        )
        return true
    }
}
```

**JotApp change:**
```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

---

### Step 4: Handle Spotlight Deep Link in ContentView
**Objective:** When a Spotlight result is tapped, navigate to that note.

**Files to Modify:**
- `Jot/App/ContentView.swift` -- add `.onReceive` for `.openNoteFromSpotlight`
- `Jot/Utils/Extensions.swift` -- add notification name

**Implementation:**
```swift
.onReceive(NotificationCenter.default.publisher(for: .openNoteFromSpotlight)) { notification in
    guard let noteID = notification.userInfo?["noteID"] as? UUID else { return }
    openNoteByID(noteID)
}
```

**`openNoteByID` function:**
- Find note in `notesManager.notes` by UUID
- If found: set `selectedNote`, `selectedNoteIDs`, `selectionAnchorID`
- If locked: present lock authentication first
- If not found in active notes: check `deletedNotes`, potentially restore

---

### Step 5: Trigger Reindex on App Launch
**Objective:** Ensure Spotlight index is current when app starts.

**Files to Modify:**
- `Jot/App/ContentView.swift` -- in the `.onAppear` block (around line 522)

**Implementation:**
Add after `reconcileSelectionWithCurrentNotes()`:
```swift
SpotlightIndexer.shared.reindexAll(notesManager.notes)
```

---

### Step 6: Create PrintCommands
**Objective:** Add File > Print menu item with Cmd+P.

**Files to Create:**
- `Jot/App/PrintCommands.swift`

**Implementation:**
```swift
struct PrintCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                NotificationCenter.default.post(name: .printCurrentNote, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }
}
```

**Files to Modify:**
- `Jot/App/JotApp.swift` -- add `PrintCommands()` to `.commands {}`
- `Jot/Utils/Extensions.swift` -- add `.printCurrentNote` and `.openNoteFromSpotlight` notification names

---

### Step 7: Implement Print in Coordinator
**Objective:** Handle the print notification and trigger NSPrintOperation.

**Files to Modify:**
- `Jot/Views/Components/TodoEditorRepresentable.swift`

**Add notification name** (after line 8155):
```swift
static let printCurrentNote = Notification.Name("PrintCurrentNote")
```

**Register observer in `configure(with:)`** (after the existing observers, ~line 1919):
```swift
let printObs = NotificationCenter.default.addObserver(
    forName: .printCurrentNote, object: nil, queue: .main
) { [weak self] notification in
    if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
       let myID = self?.editorInstanceID, nid != myID { return }
    Task { @MainActor [weak self] in
        self?.handlePrint()
    }
}
observers.append(printObs)
```

**Add `handlePrint()` method to Coordinator:**
```swift
@MainActor
private func handlePrint() {
    guard let textView = self.textView else { return }

    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
    printInfo.leftMargin = 72
    printInfo.rightMargin = 72
    printInfo.topMargin = 72
    printInfo.bottomMargin = 72
    printInfo.isHorizontallyCentered = false
    printInfo.isVerticallyCentered = false

    let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
    printOp.showsPrintPanel = true
    printOp.showsProgressPanel = true
    printOp.run()
}
```

---

### Step 8: Write Tests
**Objective:** Test SpotlightIndexer logic.

**Files to Create:**
- `JotTests/SpotlightIndexerTests.swift`

**Test Cases:**
```swift
@MainActor
func testIndexNoteCreatesSearchableItem() {
    // Verify indexNote doesn't crash and processes correctly
    let note = Note(title: "Test", content: "Body", tags: ["tag1"])
    SpotlightIndexer.shared.indexNote(note)
    // CSSearchableIndex is async -- verify no crash
}

@MainActor
func testLockedNoteIndexedWithoutContent() {
    let note = Note(title: "Secret", content: "Hidden", isLocked: true)
    // Verify the attributeSet has nil contentDescription
    // (test the attribute building logic, not CSSearchableIndex itself)
}

@MainActor
func testDeindexRemovesNotes() {
    let id = UUID()
    SpotlightIndexer.shared.deindexNotes(ids: [id])
    // Verify no crash
}

@MainActor
func testDeletedNoteIsDeindexed() {
    var note = Note(title: "Deleted", content: "Body")
    note.isDeleted = true
    SpotlightIndexer.shared.indexNote(note)
    // Should deindex, not index
}
```

---

## 5. Success Criteria

### Functional Requirements
- [ ] Notes appear in Spotlight search (Cmd+Space, type note title)
- [ ] Clicking a Spotlight result opens Jot to that note
- [ ] New notes indexed immediately after creation
- [ ] Updated notes re-indexed after save
- [ ] Deleted notes removed from Spotlight
- [ ] Archived notes removed from Spotlight
- [ ] Locked notes show title only in Spotlight (no content preview)
- [ ] Restored notes re-indexed
- [ ] Cmd+P opens native macOS print dialog
- [ ] Printed output preserves bold, italic, underline, colors, fonts
- [ ] Multi-page notes paginate correctly
- [ ] File > Print menu item visible in menu bar

### Code Quality
- [ ] SpotlightIndexer follows singleton `@MainActor` pattern
- [ ] Print uses existing notification pattern from TodoEditorRepresentable
- [ ] No responder chain conflicts
- [ ] AppDelegate follows `NSApplicationDelegateAdaptor` pattern

---

## 6. Validation Gates

### Build Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

### Test Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

---

## 7. Gotchas & Considerations

### Spotlight
- **Sandbox**: CoreSpotlight works within the app sandbox -- no additional entitlements needed
- **Index timing**: `CSSearchableIndex.indexSearchableItems()` is async but doesn't provide completion guarantees for when items appear in Spotlight. There can be a delay of several seconds.
- **Content size**: `contentDescription` should be limited to ~300 characters for Spotlight preview
- **Markup stripping**: `convertMarkupToPlainText()` is an instance method on `NoteExportService` -- need to instantiate it or make it static
- **Reindex performance**: Full reindex on launch should be debounced or done in background to not block the UI

### Printing
- **Images won't print**: They're overlay views, not NSTextAttachments. This is documented as out of scope for MVP.
- **Dark mode**: NSTextView may have light-on-dark text. For printing, should ideally force light appearance. Can set `textView.appearance = NSAppearance(named: .aqua)` before print and restore after.
- **Code blocks/tables**: Overlay views, won't appear in print. Documented as v2.
- **Print panel threading**: `NSPrintOperation.run()` must be called on main thread (we're already `@MainActor`).
- **Multiple editors**: In split view, both editors have coordinators. The notification should only be handled by the active/focused editor. Filter by `editorInstanceID` or check `textView.window?.firstResponder == textView`.

---

## 8. Implementation Checklist

- [ ] Step 1: Create SpotlightIndexer
- [ ] Build validation
- [ ] Step 2: Hook indexer into SimpleSwiftDataManager
- [ ] Build validation
- [ ] Step 3: Create AppDelegate for deep links
- [ ] Step 4: Handle deep link in ContentView
- [ ] Step 5: Trigger reindex on app launch
- [ ] Build validation
- [ ] Step 6: Create PrintCommands
- [ ] Step 7: Implement print in Coordinator
- [ ] Build validation
- [ ] Step 8: Write tests
- [ ] Test validation
- [ ] Manual testing: Spotlight search, deep link, Cmd+P

---

## 9. Confidence Assessment

**Confidence Level:** 9/10

**What's Clear:**
- All lifecycle hooks mapped with exact line numbers
- Notification pattern for printing well-understood (matches 15+ existing examples)
- Markup stripping function exists and is reusable
- `CSSearchableIndex` API is straightforward
- `NSPrintOperation(view:)` is the standard macOS printing path

**What Needs Verification:**
- Whether `NSApplicationDelegateAdaptor` conflicts with SwiftUI's own `WindowGroup` lifecycle
- Whether `convertMarkupToPlainText` needs to be static or if instantiating `NoteExportService` is fine
- Exact behavior of `NSPrintOperation(view: textView)` with custom NSTextView subclass
