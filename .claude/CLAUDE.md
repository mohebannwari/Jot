# CLAUDE.md — Jot

iOS 26+ / macOS 26+ note-taking app in SwiftUI with Apple Liquid Glass design system.

---

## Design System
→ **Always reference `.claude/DESIGN_SYSTEM.md`** for all color, spacing, typography, radius, and effect tokens.
→ Figma source: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot
→ Extract tokens for **both light and dark** themes. No exceptions.
→ Use `figma-mcp` (`get_variable_defs`, `get_design_context`) before any UI work.

---

## Context Engineering
Before any feature implementation:
1. Write `INITIAL.md` describing the feature
2. `/generate-prp INITIAL.md`
3. `/execute-prp PRPs/feature-name.md`

---

## Subagents — Haiku Model Only
Delegate all research and information gathering to subagents using **Haiku**. Never use main context for lookups.

Use Haiku subagents for:
- SwiftUI / SDK documentation (via Context7 MCP)
- Codebase file discovery and pattern search
- Figma token extraction
- API behavior confirmation

Main context = implementation only.

---

## Tool Calling & Skills

**Always invoke the right skill before acting:**

| Task | Skills |
|------|--------|
| New feature | `superpowers:brainstorming` → `superpowers:writing-plans` → `superpowers:test-driven-development` |
| Bug | `superpowers:systematic-debugging` |
| Design / UI | `figma-design` |
| Completion | `superpowers:verification-before-completion` → `superpowers:requesting-code-review` |
| Multi-task | `superpowers:dispatching-parallel-agents` |

**MCP priority:**
1. Context7 — SDK/API docs (always first)
2. Figma Dev Mode MCP — design tokens and component specs
3. Brave Search — last resort

**Always parallelize** independent file reads, searches, and tool calls.

---

## Build Commands
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
xcodebuild -project Jot.xcodeproj -scheme Jot clean
```
Check for compile errors before finalizing any implementation.

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
- Persistence: `SimpleSwiftDataManager`
- View structure: props → computed properties → body
- Never hardcode design values — always use asset catalog names

---

## Liquid Glass (iOS 26+ / macOS 26+)
Priority:
1. `.glassEffect()` — regular + capsule (default)
2. `.glassEffect(.thin, in: RoundedRectangle(cornerRadius: 20))`
3. `.glassEffect(.regular.interactive(true))`
4. Fallback: `.ultraThinMaterial`

Rules: no glass-on-glass; floating elements only; `.glassEffectID()` for morphing.

---

## Screenshot Review — UI Polish Loop

After any UI implementation, always run a visual review pass. Capture **only the Jot window**, not the full screen:

```bash
# 1. Bring Jot to front, then get its window ID
osascript -e 'tell application "Jot" to activate' && sleep 0.3

WINDOW_ID=$(swift -e '
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in windows {
    if (w["kCGWindowOwnerName"] as? String ?? "").contains("Jot") {
        if let id = w["kCGWindowNumber"] as? Int { print(id) }
    }
}
')

# 2. Capture the window
screencapture -l $WINDOW_ID /tmp/jot_window.png
```

Then read `/tmp/jot_window.png` with the `Read` tool and analyze:
- Alignment, spacing, and sizing against `.claude/DESIGN_SYSTEM.md` tokens
- Light and dark mode correctness (take both)
- Liquid Glass rendering and layering
- Typography rendering and hierarchy
- Edge cases: empty state, long text, small screens

Iterate: fix → rebuild → re-capture → re-analyze until it matches Figma spec.
At least one screenshot pass is mandatory before marking any UI task complete.

---

## Code Rules
- **iOS 26+ / macOS 26+ only.** Never reference iOS 18 or macOS 15.
- No hardcoded colors, spacing, or radii — use design tokens.
- Check existing components before creating new ones.
- Rich text: `AttributedString` + `.richTextCapabilities()`.
- Lists: `LazyVGrid` for performance.
- Broad codebase review before any bug fix — never patch symptoms.
- Always use Context7 for SwiftUI/SDK documentation.

---

## CI / GitHub Actions
Workflows live at `.github/workflows/` — this is a GitHub requirement and cannot move.
- `claude-code-review.yml` — PR review bot
- `claude.yml` — responds to `@claude` mentions in issues/PRs
