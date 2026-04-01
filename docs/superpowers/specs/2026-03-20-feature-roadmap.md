# Jot Feature Roadmap & Implementation Spec

> Created: 2026-03-20
> Status: Active
> Platform: macOS-only (no iOS planned currently)

## Context

After a comprehensive codebase audit, we identified 16 potential features across three tiers (non-negotiable, nice-to-have, simplicity). Through individual discussion, we prioritized 13 features and organized them into 6 implementation batches. Each batch is worked on a dedicated git branch, tested and refined before merging to main.

---

## Execution Workflow (Per Batch)

**This is the process for every single batch. No exceptions.**

1. **Create feature branch** from `main` (e.g., `feature/batch-1-shortcuts-undo`)
2. **Move Linear issues** to "In Progress"
3. **Write INITIAL.md** for the batch features (context engineering)
4. **Generate PRP** via `/generate-prp INITIAL.md`
5. **Execute PRP** via `/execute-prp PRPs/<feature>.md`
6. **Implement with TDD** where applicable -- write failing test first, then code
7. **Build and verify** -- `xcodebuild` must pass with zero errors
8. **Test manually** -- run the app and verify features work
9. **Code review** via `superpowers:requesting-code-review`
10. **Fix issues** from review
11. **Mark Linear issues** as "Done"
12. **Merge to main** only when stable and reviewed
13. **Move to next batch**

---

## Full Roadmap

### Batch 1: Foundation (High Priority)
**Branch:** `feature/batch-1-shortcuts-undo`
**Linear Issues:** DES-265, DES-266

| Feature | Description | Linear |
|---------|-------------|--------|
| **Comprehensive Keyboard Shortcuts** | Cmd+N (new note), Cmd+Shift+N (new folder), Cmd+1/2/3 (headings), Cmd+Delete (trash), Cmd+Shift+L (toggle list), Cmd+L (insert link), arrow-key sidebar navigation | [DES-265](https://linear.app/mohebanw/issue/DES-265) |
| **Toast-based Undo** | Floating undo toast (5s) after destructive ops: delete, move, archive, pin/unpin. Reusable `UndoToastManager` + `UndoToast` overlay | [DES-266](https://linear.app/mohebanw/issue/DES-266) |

**Why first:** Both are foundational UX improvements. Keyboard shortcuts affect how all future features are accessed. Toast undo establishes a reusable pattern.

**Key files to modify:**
- `Jot/App/ContentView.swift` -- menu bar commands, sidebar keyboard nav
- `Jot/Views/Screens/NoteDetailView.swift` -- editor shortcuts
- `Jot/Views/Components/TodoRichTextEditor.swift` -- formatting shortcuts
- New: `Jot/Utils/UndoToastManager.swift`
- New: `Jot/Views/Components/UndoToast.swift`

---

### Batch 2: System Integration (High Priority)
**Branch:** `feature/batch-2-spotlight-printing`
**Linear Issues:** DES-267, DES-268

| Feature | Description | Linear |
|---------|-------------|--------|
| **Spotlight Integration** | CSSearchableIndex for note titles/content. Deep links back to Jot. Locked notes indexed by title only. | [DES-267](https://linear.app/mohebanw/issue/DES-267) |
| **Printing (Cmd+P)** | Native NSPrintOperation. File > Print menu item. Respects formatting, images, layout. | [DES-268](https://linear.app/mohebanw/issue/DES-268) |

**Why together:** Both are macOS system integration. Independent of each other, can be developed in parallel.

**Key implementation:**
- CoreSpotlight framework, `CSSearchableIndex`, `NSUserActivity` deep linking
- `NSPrintOperation` on editor's NSTextView, File > Print menu item

---

### Batch 3: Platform Extension (High Priority)
**Branch:** `feature/batch-3-share-intents`
**Linear Issues:** DES-269, DES-270

| Feature | Description | Linear |
|---------|-------------|--------|
| **Share Extension** | macOS share sheet target. Capture URLs, text, images from any app. New extension target. App Groups for shared data. | [DES-269](https://linear.app/mohebanw/issue/DES-269) |
| **Siri Shortcuts & App Intents** | AppIntents framework: CreateNote, OpenNote, SearchNotes, AppendToNote. Surfaces in Shortcuts app and Siri. | [DES-270](https://linear.app/mohebanw/issue/DES-270) |

**Why together:** Both extend Jot beyond its own window. Share captures content IN; Shortcuts automates actions. Both may need App Groups.

---

### Batch 4: Data Safety (Medium Priority)
**Branch:** `feature/batch-4-backups-versioning`
**Linear Issues:** DES-271, DES-272

| Feature | Description | Linear |
|---------|-------------|--------|
| **Auto Local Backups** | Periodic backup of SwiftData store to user-chosen folder. Configurable frequency (daily/weekly). Restore UI. Prune old backups. | [DES-271](https://linear.app/mohebanw/issue/DES-271) |
| **Note History / Versioning** | Snapshots on significant edits. `NoteVersionEntity` model. Timeline viewer. Preview + restore. 30-day retention. | [DES-272](https://linear.app/mohebanw/issue/DES-272) |

**Why together:** Complementary data safety. Backups protect the whole DB; versioning protects individual notes.

---

### Batch 5: Auxiliary Experiences (Medium Priority)
**Branch:** `feature/batch-5-widgets-reminders`
**Linear Issues:** DES-273, DES-274

| Feature | Description | Linear |
|---------|-------------|--------|
| **Widgets (WidgetKit)** | Desktop/Notification Center widgets: pinned notes, recent notes. New WidgetKit extension target. App Groups for shared data. | [DES-273](https://linear.app/mohebanw/issue/DES-273) |
| **Reminders / Due Dates** | Optional `reminderDate` per note. UNUserNotificationCenter. Reminder picker UI. Notification deep link. | [DES-274](https://linear.app/mohebanw/issue/DES-274) |

**Why together:** Both are lightweight auxiliary experiences around the core app.

---

### Batch 6: Convenience (Low Priority)
**Branch:** `feature/batch-6-convenience`
**Linear Issues:** DES-275, DES-276, DES-277

| Feature | Description | Linear |
|---------|-------------|--------|
| **Global Quick Note Hotkey** | System-wide hotkey via NSEvent global monitor. Floating NSPanel capture window. Type, dismiss, saved. | [DES-275](https://linear.app/mohebanw/issue/DES-275) |
| **Smart Folders** | Auto-populating folders based on rules (tags, dates, todos). SmartFolderEntity + rule editor UI. | [DES-276](https://linear.app/mohebanw/issue/DES-276) |
| **Templates** | Pre-structured note starters + "Save as Template". TemplateEntity model. Template picker on new note. | [DES-277](https://linear.app/mohebanw/issue/DES-277) |

**Why three:** All convenience features. Quick Note and Templates are small scope. Smart Folders is medium. Grouped for productivity.

---

## Skipped Features

| Feature | Reason |
|---------|--------|
| Backlinks Panel | Too Obsidian-like, keep Jot simple |
| Focus Mode | Current editor is clean enough |
| Quick Capture from Clipboard | Manual paste is fine |

---

## Reference

- **CSV Roadmap:** `docs/roadmap.csv`
- **Linear Project:** [Jot on Linear](https://linear.app/mohebanw/project/jot-7b32eb207f53)
- **All issues:** DES-265 through DES-277
- **Design System:** `.claude/rules/design-system.md`
