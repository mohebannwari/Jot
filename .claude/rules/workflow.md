# Workflow -- Jot Project

Inherits all rules from the global workflow (`~/.claude/workflow.md`). This file adds Jot-specific conventions only.

Architecture, design conventions, Liquid Glass helpers, and SVG rules live in `CLAUDE.md` (not duplicated here).
Design tokens live in `design-system.md` (not duplicated here).

---

## Build & Launch

```bash
# Build
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates

# Test
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test

# Test specific suite
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/SpecificTests test -allowProvisioningUpdates
```

Check for compile errors before finalizing any implementation.

**Do not relaunch the app after building.** The user handles relaunching via the in-app updates panel.

---

## Git Conventions

- Feature branch per batch: `feature/batch-N-description`
- Linear issues: DES-XXX series, updated to In Progress at start, Done at merge
- CI: `claude-code-review.yml` (PR review bot), `claude.yml` (responds to @claude mentions)
- Delete completed PRP files in cleanup step of each batch

---

## Context Engineering

Before any feature implementation:
1. Write `INITIAL.md` describing the feature
2. `/generate-prp INITIAL.md` to create a Product Requirements Prompt
3. `/execute-prp PRPs/feature-name.md` to begin implementation

PRP templates live at `PRPs/templates/prp_base.md`. Workflows at `PRPs/workflows/`.

---

## Screenshot Capture

Only when explicitly requested. Never launch a new window.

```bash
WINDOW_ID=$(swift -e '
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in windows {
    if (w["kCGWindowOwnerName"] as? String ?? "").contains("Jot") {
        if let id = w["kCGWindowNumber"] as? Int { print(id); break }
    }
}
')
screencapture -l $WINDOW_ID /tmp/jot_window.png
```

Analyze against: alignment, spacing, sizing from design tokens, light/dark mode, Liquid Glass rendering, typography hierarchy, edge cases.

---

## Rich Text Serialization Format

Reference (for `TodoRichTextEditor`):
- `[[b]]...[[/b]]`, `[[i]]...[[/i]]`, `[[u]]...[[/u]]`, `[[s]]...[[/s]]` -- inline formatting
- `[[h1]]...[[/h1]]`, `[[h2]]`, `[[h3]]` -- headings
- `[[align:center/right/justify]]...[[/align]]` -- alignment
- `[[color|hex]]...[[/color]]` -- custom color
- `[x]` / `[ ]` -- todo checkboxes
- `[[image|||filename]]`, `[[webclip|title|desc|url]]`, `[[file|...]]`, `[[link|...]]` -- attachments

Nesting order: align > heading/bold/italic > underline > strikethrough > color
