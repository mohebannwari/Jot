# CLAUDE.md — Jot

iOS 26+ / macOS 26+ note-taking app in SwiftUI with Apple Liquid Glass design system.

---

## Subagent Architecture — Context Window is Everything

**The primary law: the lead-agent context window is sacred. Never pollute it with lookups, searches, or doc reads.**

### Model Hierarchy

| Model | Role | When to use |
|-------|------|-------------|
| **Opus** | Lead agent (user-selected) | The hardest problems — deep architecture decisions, ambiguous cross-cutting requirements, designs that need genuine reasoning. User selects Opus manually. |
| **Sonnet** | Default lead agent | Implementation, planning, multi-file edits, most features. **Sonnet must escalate to Opus without hesitation when the problem demands it — that's not weakness, it's judgement.** |
| **Haiku** | Fire-and-forget worker | Single-purpose lookups that have no business in the main context. Spin it and move on. |

### Fire & Forget — Delegation Rules

Spawn subagents immediately. Never block waiting for trivial information.

```
Haiku (fire immediately — don't wait, don't think twice):
- SwiftUI / SDK documentation (Context7)
- Codebase file discovery and pattern search
- Figma token extraction (get_variable_defs, get_design_context)
- Asset catalog structure checks
- API behavior confirmation

Sonnet subagents (parallel heavy lifting):
- Isolated feature implementation in a worktree
- Complex multi-file analysis
- Test writing / validation runs
- Code review on a specific component

Opus (escalation only — not parallel, not fire-and-forget):
- Escalate when Sonnet is genuinely stuck
- Consult before major architectural decisions
- User controls when Opus leads
```

### Hard Rules

1. **Information gathering never happens in main context.** Spawn Haiku, get result, use it.
2. **Parallelize all independent subagent calls.** Multiple Haiku agents running simultaneously is the goal.
3. **Sonnet asks Opus for help — no shame in it.** Thrashing in main context is worse than escalating.
4. **Opus is user-selected as primary lead for the hardest work.** Sonnet runs day-to-day.
5. **Long file dumps, full grep results, entire doc pages = subagent territory.** Not here.

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

**After every build, kill the running instance and launch the new binary:**
```bash
pkill -x Jot 2>/dev/null
touch ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
killall iconservicesagent 2>/dev/null || true
sleep 1 && open ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
```
This is mandatory after every code change — never leave a stale build running. The `touch` + `killall iconservicesagent` forces macOS to flush the icon cache so the correct icon renders immediately.

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
- Sidebar row height: 34pt for all note rows (NoteListCard, split containers, placeholders)
- Concentric corner radii: outer container 12, inner = outer - padding (e.g., pinned notes: container 12, padding 4, inner cards 8)
- Forced-appearance containers: split session containers use hardcoded `Color.white` + `.black` text (intentional — theme-independent by design)

---

## Liquid Glass (iOS 26+ / macOS 26+)
Variants (from the `Glass` type):
- `.regular` — default for toolbars, buttons, navigation (adapts to any content)
- `.clear` — floating controls over media (photos, maps); needs bold foreground
- `.identity` — disables glass conditionally (cleaner than if/else branching)

Modifiers (chain on any variant):
- `.tint(color)` — semantic coloring integrated into the glass material
- `.interactive()` — scaling, bounce, shimmer on press (interactive elements only)

Shapes: `Capsule()` (default), `RoundedRectangle(cornerRadius:)`, `Circle()`, `.rect(cornerRadius: .containerConcentric)`

Morphing: `.glassEffectID(id, in: namespace)` inside `GlassEffectContainer`

Helpers (in `GlassEffects.swift`):
- `liquidGlass(in:)` — standard interactive glass
- `tintedLiquidGlass(in:tint:)` — glass with native `.tint()` color
- `thinLiquidGlass(in:)` — plain glass without interactivity
- `prominentGlassStyle()` — `.glassProminent` button style
- `glassID(_:in:)` — morphing ID wrapper
- Fallback: `.ultraThinMaterial` (pre-26 path)

Rules: no glass-on-glass; floating elements only; coordinate morphing with `GlassEffectContainer`.

---

## Screenshot Review — UI Polish Loop

**Do NOT take screenshots automatically.** Only capture screenshots when the user explicitly asks for one.

**NEVER launch a new app window.** The user already has Jot running. Capture the existing window — do not use `open` on the built `.app` bundle. To screenshot the already-running window:

```bash
# Get the existing Jot window ID (do NOT activate/launch a new instance)
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

When requested, analyze against:
- Alignment, spacing, and sizing from `.claude/DESIGN_SYSTEM.md` tokens
- Light and dark mode correctness
- Liquid Glass rendering and layering
- Typography rendering and hierarchy
- Edge cases: empty state, long text, small screens

---

## SVG Icon Rules

### Asset Catalog — Required Properties
Every `.imageset/Contents.json` **must** include both flags in `properties`:
```json
"properties": {
  "template-rendering-intent": "template",
  "preserves-vector-representation": true
}
```
Without `preserves-vector-representation`, Xcode rasterizes SVGs as 1x bitmaps at build time. On Retina displays those bitmaps scale up = blur. **Always verify this when adding new icon assets.**

### Stroke Weight — Consistency Formula
Icons in the app come from different Figma grid sizes. When displayed at the same frame size in SwiftUI, stroke weights must be normalized so all icons look visually equal weight.

**Target stroke ratio: `1/12` of viewBox size (≈ 0.0833)**

| Figma grid | Correct stroke-width | Formula |
|------------|----------------------|---------|
| 10 × 10    | 0.833                | 10 ÷ 12 |
| 12 × 12    | 1.0                  | 12 ÷ 12 |
| 15 × 15    | 1.25                 | 15 ÷ 12 |
| 16 × 16    | 1.333                | 16 ÷ 12 |
| 18 × 18    | 1.5                  | 18 ÷ 12 |
| 20 × 20    | 1.667                | 20 ÷ 12 |
| 24 × 24    | 2.0                  | 24 ÷ 12 |

When exporting or editing an SVG, calculate: `stroke-width = viewBox_size ÷ 12`.

Icons that deviate from this ratio will appear thinner or heavier than their siblings when scaled to the same SwiftUI frame. Fix the SVG source, not the frame size.

### SVG Rotation in SwiftUI
Figma may export SVGs in the wrong orientation. To rotate (e.g., horizontal to vertical):
`.frame(width: W, height: H).rotationEffect(.degrees(90)).frame(width: H, height: W)`
First frame renders at native proportions, rotation flips visually, second frame constrains layout space.

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
