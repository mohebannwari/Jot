# Refactor Baseline - 2026-04-23

Branch: `codex/refactor-01-baseline-tests`
Base snapshot: `8ef4dd1 chore: snapshot current state before refactor`
Backup tag: `backup/pre-refactor-2026-04-23`

## Preservation Check

`origin/main` and `backup/pre-refactor-2026-04-23` both point to `8ef4dd1f9567462f114fb85455a6ace855885528`.

## Baseline Test Status

Command:

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

Result: passed.

Summary:

- 307 tests executed.
- 0 failures.
- Result bundle: `/Users/mohebanwari/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Logs/Test/Test-Jot-2026.04.23_23-52-44-+0200.xcresult`

Environment note:

- Xcode emitted a CoreSimulator version mismatch warning before the macOS test run. The macOS destination still built and ran successfully.

## Baseline Correction

The first full baseline run failed in `MapBlockOverlayViewTests/testHitTestCapturesBottomEdgeFromSuperviewCoordinates`.

Root cause: the test used `overlay.frame.maxY - 2` as the bottom-edge point in superview coordinates. `MapBlockOverlayView` is flipped, so that point converts to local `y = 2`, which is the top resize zone. The corrected bottom-edge point is `overlay.frame.minY + 2`, which converts near `bounds.maxY`.

Production code was not changed.

## Characterization Coverage

Existing coverage already guards the major phase-01 refactor surfaces:

- Editor serialization: `NoteSerializerTests`, `RichTextSerializerTests`, `CodeBlockDataTests`, `CalloutDataTests`, `TabsContainerDataTests`, `MapBlockDataTests`.
- Attachment insertion and editor bridge behavior: `TodoEditorInsertRegressionTests`.
- Note selection: `NoteSelectionInteractionTests`, `NoteSelectionPolicyTests`.
- Command menu and palette-related behavior: `CommandMenuLayoutTests`, `TodoEditorInsertRegressionTests`, `SearchEngineTests`.
- HTML/export and Quick Look rendering: `NoteExportServiceTests`, `NoteMarkupHTMLRendererTests`, `NoteQuickLookTests`.

Added coverage:

- `SplitSessionPersistenceTests` now verifies `SplitSession` Codable round-tripping for complete sessions and incomplete sessions.

## Safety Checks

Command:

```bash
git diff --check
```

Result: passed.
