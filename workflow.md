# Workflow -- Jot Project

Inherits all rules from the global workflow (`~/.claude/workflow.md`). This file adds Jot-specific conventions only.

---

## Project Identity

- iOS 26+ / macOS 26+ note-taking app in SwiftUI
- Apple Liquid Glass design system
- Figma source: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot

---

## Context Engineering (Jot)

Before any feature implementation:
1. Write `INITIAL.md` describing the feature
2. `/generate-prp INITIAL.md` to create a Product Requirements Prompt
3. `/execute-prp PRPs/feature-name.md` to begin implementation

PRP templates live at `PRPs/templates/prp_base.md`. Workflows at `PRPs/workflows/`.

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

# Kill + relaunch (mandatory after every build)
pkill -x Jot 2>/dev/null
touch ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
killall iconservicesagent 2>/dev/null || true
sleep 1 && open ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
```

The `touch` + `killall iconservicesagent` forces macOS to flush the icon cache.

---

## Architecture

```
Jot/
├── App/              # JotApp.swift, ContentView.swift
├── Models/           # Note.swift, Folder.swift, SwiftData/
├── Views/
│   ├── Components/   # Reusable UI
│   └── Screens/      # Full-screen views
├── Utils/            # ThemeManager, FontManager, Extensions
└── Ressources/       # Assets.xcassets (color sets, images)
```

**Patterns:**
- State: `@StateObject` / `@EnvironmentObject` (NotesManager, ThemeManager)
- Persistence: `SimpleSwiftDataManager` (SwiftData with `ModelContainer`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide
- View structure: props -> computed properties -> body
- One primary type per file

---

## Liquid Glass (iOS 26+ / macOS 26+)

**Variants:** `.regular`, `.clear`, `.identity`

**Modifiers:** `.tint(color)`, `.interactive()`

**Helpers** (in `GlassEffects.swift`):
- `liquidGlass(in:)` -- standard interactive glass
- `tintedLiquidGlass(in:tint:)` -- glass with native `.tint()` color
- `thinLiquidGlass(in:)` -- plain glass without interactivity
- `prominentGlassStyle()` -- `.glassProminent` button style
- `glassID(_:in:)` -- morphing ID wrapper

**Shapes:** `Capsule()` (default), `RoundedRectangle(cornerRadius:)`, `Circle()`

**Rules:**
- No glass-on-glass.
- Floating elements only.
- Coordinate morphing with `GlassEffectContainer`.
- Fallback: `.ultraThinMaterial` for pre-26.

---

## SVG Icon Rules

**Asset Catalog:** Every `.imageset/Contents.json` must include:
```json
"properties": {
  "template-rendering-intent": "template",
  "preserves-vector-representation": true
}
```

**Stroke Weight:** `stroke-width = viewBox_size / 12` for consistent visual weight across grid sizes.

| Figma grid | Correct stroke-width |
|------------|---------------------|
| 10 x 10   | 0.833               |
| 12 x 12   | 1.0                 |
| 16 x 16   | 1.333               |
| 24 x 24   | 2.0                 |

**Rotation** (when Figma exports wrong orientation):
`.frame(width: W, height: H).rotationEffect(.degrees(90)).frame(width: H, height: W)`

---

## Design System

- Reference `.claude/DESIGN_SYSTEM.md` for all color, spacing, typography, radius, and effect tokens.
- Never hardcode colors, spacing, or radii -- use asset catalog names.
- `NSColor.labelColor` everywhere -- no hardcoded dark/light RGB tuples.
- Sidebar row height: 34pt for all note rows.
- Concentric corner radii: outer container 16, inner = outer - padding (e.g., container 16, padding 4, inner 12).

---

## Jot-Specific Prohibitions

- Never `.clipped()` or `.clipShape()` on parent containers unless explicitly requested.
- Split session containers use hardcoded `Color.white` + `.black` text -- intentional, theme-independent by design.

---

## Git Conventions (Jot)

- Feature branch per batch: `feature/batch-N-description`
- Linear issues: DES-XXX series, updated to In Progress at start, Done at merge
- CI: `claude-code-review.yml` (PR review bot), `claude.yml` (responds to @claude mentions)
- Delete completed PRP files in cleanup step of each batch

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
