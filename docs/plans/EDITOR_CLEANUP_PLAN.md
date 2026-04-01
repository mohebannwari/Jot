# Rich Text Editor Cleanup & Hardening Plan

## Context

Four parallel audit agents analyzed Jot's rich text editor (~9100 lines in TodoEditorRepresentable.swift) across storage, behavior, robustness, and market standards. Every single finding is addressed below -- nothing deferred, nothing deprioritized. All issues are P0.

Each batch is executed independently. Build, test, and verify before proceeding to the next batch.

---

## Batch 1 -- Data Safety

### 1.1 Image cleanup regex deletes resized images
**File:** `Jot/Utils/ImageStorageManager.swift` ~line 122
**Bug:** Regex `[^\]]+` captures `foo.jpg|||0.3300` instead of just `foo.jpg`. Resized images get deleted on restart.
**Fix:** Change capture group from `[^\]]+` to `[^\]|]+` (exclude both `]` and `|`).

### 1.2 Pasted clipboard images silently lost on round-trip
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 7716-7828
**Bug:** Clipboard images (TIFF/PNG) arrive as `NSTextAttachment` with `fileWrapper`. Serializer only handles `.jpg` -- non-jpg attachments emit U+FFFC as literal text, image vanishes on deserialize.
**Fix:** Intercept `NSPasteboard` image types in paste handler, convert to JPEG, save via `ImageStorageManager.saveImage`, insert as `[[image|||]]`. Add serializer fallback for non-jpg file wrapper attachments.

### 1.3 File attachment storage leak (no cleanup)
**File:** `Jot/Utils/FileAttachmentStorageManager.swift`
**Bug:** No `cleanupUnusedFiles()` exists. `JotFiles/` grows unbounded when notes are deleted.
**Fix:** Add `cleanupUnusedFiles(referencedIn:)` mirroring `ImageStorageManager.cleanupUnusedImages`. Wire into `SimpleSwiftDataManager.loadNotes(isInitialLoad: true)`.

### 1.4 Block-tag parse failure silently corrupts document display
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 7111-7254
**Bug:** When `[[table|...]]`, `[[callout|...]]`, etc. fail to deserialize, raw markup renders as visible text.
**Fix:** On parse failure, emit entire block as a styled "corrupted block" placeholder preserving raw text in an attribute for re-serialization without data loss.

### 1.5 `emptyTrash`/`permanentlyDeleteNotes` don't trigger image cleanup
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` ~lines 688-733
**Bug:** When notes are permanently deleted, their images remain on disk until next app restart.
**Fix:** Call `ImageStorageManager.cleanupUnusedImages` (and the new file cleanup) after permanent deletion.

### 1.6 `ensureStorageDirectoryExists` is fire-and-forget in `init()`
**File:** `Jot/Utils/ImageStorageManager.swift` ~lines 31-36
**Bug:** `saveImage(from:)` can be called before the async `init()` task completes, causing write failure.
**Fix:** Call `ensureStorageDirectoryExists()` inside `saveImage` before writing, not just in `init`.

### 1.7 Insert default `widthRatio` mismatch with deserialization default
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 4844, 7075
**Bug:** New images insert at `0.33` ratio, but deserialization defaults to `1.0` when ratio tag is missing/corrupted. A stripped ratio flips from small to full-width.
**Fix:** Align both defaults to the same value (either both `0.33` or both `1.0`), or always serialize the ratio.

### 1.8 `cleanupUnusedImages` rebuilds regex per-note inside loop
**File:** `ImageStorageManager.swift` ~line 122
**Bug:** The `NSRegularExpression` is compiled fresh on every iteration of the note loop.
**Fix:** Compile regex once outside the loop (like `ThumbnailCache` already does at line 105).

### 1.9 `cleanupUnusedImages` runs synchronously on `@MainActor`
**File:** `Jot/Utils/ImageStorageManager.swift` ~lines 111-161
**Bug:** Regex matching and file deletion both block the main thread. Heavy for users with many notes/images.
**Fix:** Keep referenced-set building on main actor, move directory enumeration and file deletion to `Task.detached(priority: .background)`.

### 1.10 `updateNote` silently drops sticker encoding failure
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` ~lines 437-444
**Bug:** If `JSONEncoder().encode(updatedNote.stickers)` throws, the catch logs the error but leaves `noteEntity.stickersData` stale while the in-memory model is already updated. Entity and memory diverge.
**Fix:** On encoding failure, also revert the in-memory stickers to match the entity, or re-throw to surface the error.

### Batch 1 Verification
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```
Manual tests:
- Insert image, resize it, quit/relaunch -- image must survive
- Paste screenshot from clipboard (Cmd+Shift+4) -- must persist after relaunch
- Delete note with file attachment, relaunch -- orphaned files cleaned up
- Corrupt a block tag manually -- should show placeholder, not raw markup
- Empty trash -- images from deleted notes should be cleaned up immediately
- Add sticker to note, verify persistence after relaunch

---

## Batch 2 -- Undo & Editor Correctness

### 2.1 Bullet/dash list toggles bypass undo
**File:** `Jot/Utils/TextFormattingManager.swift` ~lines 368-384, 805-823
**Bug:** `toggleBulletList` and `toggleDashedList` call `textStorage.replaceCharacters` directly without `shouldChangeText/didChangeText`. Invisible to NSUndoManager.
**Fix:** Wrap in `textView.shouldChangeText(in:replacementString:)` / `textView.didChangeText()`.

### 2.2 All formatting operations skip `shouldChangeText`/`didChangeText`
**File:** `Jot/Utils/TextFormattingManager.swift`
**Bug:** `applyBodyStyle`, `applyHeading`, `adjustIndentation`, `setAlignment`, `toggleBlockQuote` modify storage via `beginEditing/endEditing` but never call the delegate contract methods. `changeCount` not incremented, undo entries not properly coalesced.
**Fix:** Audit every method in `TextFormattingManager` that modifies text storage. Add `shouldChangeText/didChangeText` calls.

### 2.3 Block-level insertions create wrong-scope undo actions
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** `insertTable`, `insertCallout`, `insertCodeBlock`, `insertTabs`, `insertCardSection`, `insertDivider` set `isUpdating = true` before `shouldChangeText`, causing `textDidChange` to bail. Undo reverts further than expected.
**Fix:** Set `isUpdating` after `shouldChangeText`, not before. Or group the insertion as a named undo action.

### 2.4 Context menu formatting broadcasts to ALL editors in split view
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 8802-8820
**Bug:** Notifications post without `editorInstanceID`. Both split-view editors respond.
**Fix:** Include `"editorInstanceID": editorInstanceID` in every context menu notification's `userInfo`.

### 2.5 `storage.edited()` called outside `beginEditing/endEditing` -- crash risk
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 8913
**Bug:** `storage.edited(.editedAttributes, ...)` fires after `storage.endEditing()` in checkbox toggle.
**Fix:** Move `storage.edited()` inside the bracket, before `endEditing()`.

### 2.6 `cardSectionOverlays` not cleaned up in `deinit` -- memory leak
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 2063
**Bug:** All overlay types cleaned up in deinit except `cardSectionOverlays`.
**Fix:** Add `cardSectionOverlays` to the deinit cleanup block.

### 2.7 Strikethrough applies todo-dimmed color to non-todo text
**Files:** `TextFormattingManager.swift` ~line 358; `TodoEditorRepresentable.swift` ~line 7659
**Bug:** `toggleStrikethrough` unconditionally applies `checkedTodoTextColor` to any strikethrough text.
**Fix:** Only apply `checkedTodoTextColor` when text is in a todo paragraph. Keep `NSColor.labelColor` for non-todo text.

### 2.8 `recomputeDerivedNotes` missing `objectWillChange.send()`
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` ~line 192
**Bug:** Comment says `objectWillChange` is sent here, but it's not. Derived collections not invalidated.
**Fix:** Add `objectWillChange.send()` at the top of `recomputeDerivedNotes()`.

### 2.9 Heading detection by font size is fragile
**Files:** `TodoEditorRepresentable.swift` ~line 7594; `TextFormattingManager.swift` ~lines 26-33
**Bug:** `headingLevel(for:)` switches on `font.pointSize` (H1=32, H2=24, H3=20). If body font is configured near 20pt, body text is misidentified as H3.
**Fix:** Use a custom font attribute marker (e.g., `.headingLevel`) instead of inferring from point size.

### 2.10 `updateFormattingState` only checks first attribute run
**File:** `Jot/Utils/TextFormattingManager.swift` ~lines 761-795
**Bug:** All `enumerateAttribute` calls pass `stop.pointee = true` after first match. Mixed-formatting selections show whatever the first character has.
**Fix:** Enumerate full selection. Report "bold" only if all characters are bold (or use "any bold" convention -- match Apple Notes behavior).

### 2.11 `applyBodyStyle` doesn't clear all formatting attributes
**File:** `Jot/Utils/TextFormattingManager.swift` ~lines 165-197
**Bug:** Clears font, underline, strikethrough, paragraph style. Does NOT clear `.foregroundColor`, `.backgroundColor`, `.link`, `.highlightColor`. Custom colors persist through body reset.
**Fix:** Clear all formatting attributes when resetting to body style.

### 2.12 Markdown inline shortcuts break undo into two steps
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 8656
**Bug:** Typing `**bold**` creates two undo actions: one for the shortcut replacement, one for the typed characters. Users must Cmd+Z twice.
**Fix:** Group the shortcut replacement into the same undo group as the character insertion.

### 2.13 `dismissCommandMenu` async double-dismiss flicker
**File:** `Jot/Views/Components/TodoRichTextEditor.swift` ~lines 514-544
**Bug:** `dismissCommandMenu()` dispatches async `.hideCommandMenu` which calls `dismissCommandMenu()` again. Race between keyboard and notification dismiss causes visible flicker.
**Fix:** Remove the recursive call or add a dedicated `isDismissing` guard that covers both paths.

### 2.14 `importBackup` doesn't sort notes
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` ~lines 1098-1148
**Bug:** After importing, `self.notes` is assigned from raw backup array with arbitrary order.
**Fix:** Sort the imported notes by `modifiedAt` descending before assignment, or ensure `recomputeDerivedNotes()` handles it.

### 2.15 `maxLoadLimit = 500` silently hides notes
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` ~line 48
**Bug:** Users with >500 notes find notes absent from sidebar. `loadMoreNotes(offset:)` exists but has no call site.
**Fix:** Wire `loadMoreNotes` to the sidebar scroll (lazy loading), or surface a "Load More" button when the cap is hit.

### 2.16 Proofread suggestion replaces first literal match only
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 3039, 3077
**Bug:** `applyProofreadSuggestion` uses `range(of:options:.literal)` -- first match only. Duplicate text may cause wrong occurrence to be replaced.
**Fix:** Track the original range from the proofread overlay and replace by range, not by text search.

### 2.17 `insertTextAtCursor` strips leading/trailing whitespace
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 4804
**Bug:** AI-generated text that intentionally starts with a newline has it silently stripped.
**Fix:** Remove `trimmingCharacters(in: .whitespacesAndNewlines)` or make it configurable.

### Batch 2 Verification
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```
Manual tests:
- Toggle bullet list, Cmd+Z -- must undo cleanly
- Apply bold, italic, heading -- Cmd+Z must revert each
- Right-click > Bold in split view -- only active editor affected
- Toggle checkbox rapidly -- no crash
- Navigate notes repeatedly -- no increasing memory from card overlays
- Strikethrough on non-todo text -- should stay label color
- Edit note, check sidebar updates immediately
- Apply heading then reset to body -- custom colors should clear
- Type `**bold**` then Cmd+Z once -- should revert entire shortcut
- Import backup -- notes should appear in correct order
- Proofread suggestion on duplicate word -- correct occurrence replaced

---

## Batch 3 -- Missing Standard Features & Editor Polish

### 3.1 No Cmd+B / Cmd+I / Cmd+U keyboard shortcuts
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Most fundamental macOS formatting shortcuts absent.
**Fix:** Add handling in `performKeyEquivalent` dispatching to `TextFormattingManager`.

### 3.2 IME composition triggers `@`/`/` interceptors
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 8430
**Bug:** CJK users typing `@` mid-composition trigger note picker.
**Fix:** Guard with `guard !hasMarkedText()`.

### 3.3 `insertLink` is a Markdown stub
**File:** `Jot/Utils/TextFormattingManager.swift` ~line 650
**Bug:** Inserts literal `[text](url)` instead of `.link` attribute.
**Fix:** Apply `.link` attribute with URL value, style with accent color + underline.

### 3.4 NSCache cost limit is dead code
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 5427, 4825
**Bug:** `setObject` without cost argument. 50MB limit never enforced.
**Fix:** Pass `cost: Int(img.size.width * img.size.height * 4)`.

### 3.5 Paste discards all incoming rich formatting
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 7716-7828
**Bug:** Paste reads only `NSPasteboard.string(forType: .string)`. Rich text from Safari, Pages, Word loses all formatting.
**Fix:** Read RTF/RTFD pasteboard types, convert attributes to Jot's formatting model (bold, italic, underline, links, headings).

### 3.6 `pasteAsPlainText` skips URL/code detection
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 7965
**Bug:** Cmd+Shift+V bypasses URL paste detection that regular paste triggers.
**Fix:** Run URL/code detection after `pasteAsPlainText` as well.

### 3.7 Pill attachments blurry on display scale change
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Notelink, file link, webclip pills are rendered as bitmaps via `ImageRenderer`. No backing-scale-change handler, so they blur on external displays.
**Fix:** Listen for `NSWindow.didChangeBackingPropertiesNotification` and re-render pill attachments when scale changes.

### 3.8 Typing attribute inheritance bleeds from attachment characters
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 3902-3930
**Bug:** `textDidChange` reads `loc = sel.location - 1` for typing attributes. If cursor is after an NSTextAttachment, attachment-scoped attributes (`.attachment`, `.baselineOffset`, block `.paragraphStyle`) bleed into subsequent typed text.
**Fix:** Skip backward over attachment characters when looking for the left-neighbor attributes.

### 3.9 `isLikelyCode` false positives for prose with parentheses
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** `\w+\(` matches English like "function (which is called)". Medium-signal count >= 2 triggers code paste prompt on normal prose.
**Fix:** Tighten the regex to require no space before `(`, e.g., `\w+\(` becomes `\w+\(` with additional check that the match doesn't have a space before `(`. Or raise the threshold.

### 3.10 Block quote Enter doesn't break out on empty line
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Pressing Enter at end of block quote always creates another quoted paragraph. No way to exit except double-Enter on empty line (differs from Notion/Bear single-Enter exit).
**Fix:** When Enter is pressed on an empty block quote line, remove the quote formatting and exit the block.

### 3.11 Spell check interacts with attachment characters
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** U+FFFC characters from NSTextAttachments cause spell check to show red underlines at unusual word boundaries near inline images/checkboxes.
**Fix:** Mark attachment character ranges with `.spellingState: 0` or use `NSSpellChecker` exclusion to skip them.

### 3.12 Drag-and-drop may lose custom attachment types
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Dragging custom attachments (NoteImageAttachment, NoteTableAttachment, etc.) within the editor round-trips through NSPasteboard's RTFD type, losing custom subclass identity.
**Fix:** Override `draggingSession` and `acceptableDragTypes` to handle custom attachment types, or disable internal text drag for attachment ranges.

### 3.13 Writing Tools may persist half-modified document
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 1533
**Bug:** Writing Tools callback doesn't set `isUpdating = true`, so `textDidChange` fires `syncText()` mid-Writing-Tools session, potentially persisting incomplete edits.
**Fix:** Set `isUpdating = true` during Writing Tools processing (detect via `textBeforeWritingTools` being non-nil).

### 3.14 No `Cmd+0` shortcut to reset paragraph to body style
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Cmd+1/2/3 toggle headings but there's no direct shortcut to reset to body.
**Fix:** Add Cmd+0 handler that calls `TextFormattingManager.applyBodyStyle`.

### 3.15 `baseTypingAttributes(for:)` has dead `ColorScheme` parameter
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~line 7611
**Bug:** Accepts `colorScheme: ColorScheme?` but ignores it. All call sites pass it uselessly.
**Fix:** Remove the parameter or implement the color scheme adaptation.

### 3.16 `clampedNotePickerPosition` doesn't flip above/below
**File:** `Jot/Views/Components/TodoRichTextEditor.swift` ~lines 581-614, 684-694
**Bug:** Note picker position clamped against raw `CGSize`, not `GeometryProxy`. No above/below flip logic. Picker may go off-screen at bottom of editor.
**Fix:** Implement the same `GeometryProxy`-based flip logic used by the command menu.

### 3.17 No `Cmd+F` wired to find/replace
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Editor has custom find/replace via notifications but no `Cmd+F` override. Standard `NSTextView.usesFindBar` not enabled.
**Fix:** Wire `Cmd+F` in `performKeyEquivalent` to trigger the custom find system, or enable `usesFindBar`.

### 3.18 Context menu notification stale `urlPasteRange`
**File:** `Jot/Views/Components/TodoRichTextEditor.swift` ~lines 439-498
**Bug:** When `urlPasteDetected` handler exits via guard, stale `urlPasteRange` from previous paste may be used in subsequent operations.
**Fix:** Reset `urlPasteRange` to a safe default on guard exit.

### Batch 3 Verification
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```
Manual tests:
- Cmd+B/I/U must toggle formatting
- Cmd+0 must reset to body style
- Cmd+F must open find
- CJK input with @ during composition -- no picker popup
- Toolbar link insertion -- real hyperlink, not markdown
- Paste rich text from Safari -- formatting preserved
- Cmd+Shift+V paste URL -- detection still works
- Move window between displays -- pill attachments re-render crisp
- Type after inline image -- no paragraph style bleeding
- Paste normal English with parentheses -- no false code detection
- Enter on empty block quote line -- exits quote
- Drag text with inline image -- attachment survives
- Note picker at bottom of editor -- picker flips above cursor

---

## Batch 4 -- Performance & Stability

### 4.1 `isUpdating` guard on `fixInconsistentFonts` is always satisfied
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Dispatched async after `syncText()`, but `isUpdating` is already false. Runs on every keystroke unconditionally.
**Fix:** Debounce with a 300ms timer instead of relying on `isUpdating`.

### 4.2 Typing animation timer should use CVDisplayLink
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` / `TypingAnimationLayoutManager`
**Bug:** `Timer.scheduledTimer` at 1/120s blocks main run loop.
**Fix:** Replace with `CVDisplayLink` for frame-aligned rendering.

### 4.3 9-10 sequential O(n) passes per keystroke in `syncText`
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** `styleTodoParagraphs()` + `serialize()` + 6 overlay update passes, all O(n), all synchronous on main thread per keystroke.
**Fix:** Coalesce overlay updates into a single `enumerateAttributes` pass. Debounce `serialize()` separately from `styleTodoParagraphs()`. Only process changed paragraph ranges, not the full text storage.

### 4.4 `styleTodoParagraphs()` has quadratic complexity
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Outer paragraph loop x inner `enumerateAttribute(.attachment)` per paragraph.
**Fix:** Single-pass enumeration of attachments across full range, then map to paragraphs.

### 4.5 Image cache thrashing at >24 images
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** `countLimit = 24` causes eviction churn in image-heavy notes. Scroll-up re-triggers disk reads.
**Fix:** Increase `countLimit` to match reasonable usage (e.g., 48 or 64), with proper cost-based eviction (see 3.4).

### 4.6 `TypingAnimationLayoutManager` scales linearly with paste size
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Pasting large text queues all characters for animation simultaneously. 120Hz invalidation per character.
**Fix:** Cap the animation queue (e.g., max 50 characters). Skip animation for paste operations that insert more than N characters.

### 4.7 `recomputeDerivedNotes` fires on every `updateNote` call
**File:** `Jot/Models/SwiftData/SimpleSwiftDataManager.swift`
**Bug:** Per-keystroke content saves trigger full O(n log n) sort + 9-bucket partition over entire notes array.
**Fix:** `updateNote` should use `updateNoteInDerivedCollections` (targeted update) instead of triggering full recomputation. Only trigger full recompute when sort-affecting fields change (date, title, pin status, folder).

### 4.8 `inlineImageCache` fallback 4:3 ratio causes visible reflow
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift` ~lines 1882-1889, 5351-5371
**Bug:** Cold cache renders all images at 4:3, then corrects. Visible jump on every app open with images.
**Fix:** Store aspect ratio in the markup tag (e.g., `[[image|||foo.jpg|||0.33|||1.778]]`) to eliminate reflow.

### 4.9 `TypingAnimationLayoutManager.drawGlyphs` crash risk during mid-edit
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** `characterIndexForGlyph(at:)` called during custom drawing pass may access stale glyph maps if timer fires mid-edit.
**Fix:** Guard `drawGlyphs` with a check that the text system is not mid-edit (check `textStorage?.editedMask == []` or similar).

### 4.10 `isUpdating` boolean is a fragile reentrancy guard
**File:** `Jot/Views/Components/TodoEditorRepresentable.swift`
**Bug:** Plain `Bool` gates a deeply nested async chain. Async dispatches always find it `false`.
**Fix:** Replace with a proper reentrancy counter or use `DispatchQueue`-based serialization for the text processing pipeline.

### Batch 4 Verification
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```
Manual tests:
- Type in a 500-paragraph note -- no perceptible lag
- Paste 1000 words of text -- animation smooth, no main thread block
- Open note with 30+ images -- no excessive disk reads during scroll
- Rapid typing during Writing Tools -- no crash
- Edit note content -- sidebar doesn't visibly re-sort on every keystroke

---

## Files Modified Summary

| File | Batches |
|------|---------|
| `Jot/Utils/ImageStorageManager.swift` | 1 |
| `Jot/Views/Components/TodoEditorRepresentable.swift` | 1, 2, 3, 4 |
| `Jot/Utils/FileAttachmentStorageManager.swift` | 1 |
| `Jot/Models/SwiftData/SimpleSwiftDataManager.swift` | 1, 2, 4 |
| `Jot/Utils/TextFormattingManager.swift` | 2, 3 |
| `Jot/Views/Components/TodoRichTextEditor.swift` | 2, 3 |

---

## Total Issue Count

| Batch | Issues |
|-------|--------|
| Batch 1 -- Data Safety | 10 |
| Batch 2 -- Undo & Correctness | 17 |
| Batch 3 -- Features & Polish | 18 |
| Batch 4 -- Performance & Stability | 10 |
| **Total** | **55** |
