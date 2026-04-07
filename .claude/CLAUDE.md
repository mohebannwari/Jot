# CLAUDE.md -- Jot

iOS 26+ / macOS 26+ note-taking app in SwiftUI with Apple Liquid Glass design system.

---

## Prohibited -- Read This First

These rules are absolute. No exceptions. No rationalizations. No "just this once."

1. **Never guess when debugging.** Every bug -- regardless of how trivial, minor, or "obvious" it seems -- requires root cause investigation before any fix is attempted. Dispatch subagents to research the problem. Read documentation. Check entitlements, plists, build settings, sandbox permissions. The cost of one proper investigation is always less than four wrong guesses. If you catch yourself thinking "let me just try changing X," stop. You are about to waste time.

2. **No log-based debugging.** Do not add `NSLog`, `print()`, `os_log`, or any temporary logging statements to diagnose issues. Logs pollute the codebase, require rebuild-relaunch cycles, and encourage guess-and-check instead of thinking. Use subagents to research the problem, read Apple documentation via Context7/WebSearch, check system configuration (entitlements, plist, sandbox), and reason about the architecture. If you need runtime observation, use Xcode's debugger, not log statements.

3. **No fix without root cause.** Proposing a fix before identifying the root cause is prohibited. "I think it might be X" is not a root cause. A root cause is: "The app sandbox requires `com.apple.security.print` for `NSPrintOperation` to function, and this entitlement is missing from Jot.entitlements." Specificity or silence.

---

## Thinking & Effort

- **Effort level must always be set to maximum.** This is the default. Never reduce effort, never use low-effort or quick modes. Every response gets full reasoning depth, no matter how simple the task appears.
- Ultra think after every prompt. Full depth, full rigor, always.

---

## 95% Confidence & Clarification Rule

Before any significant action (editing, refactoring, running commands, architectural decisions), you must be **95% confident** you understand the goal, scope, and impact. If below that threshold, **stop and escalate** -- don't guess, don't assume, don't "just try it."

- **Act** when intent is unambiguous and risk is low or reversible.
- **Escalate** when ambiguous: state what's unclear, cite evidence (`file:line`), list unknowns, propose a default with trade-offs, and ask for approval.
- **Re-check** whenever new ambiguity surfaces mid-task. Confidence decays -- reassess at each decision point.

If you catch yourself writing "I'll assume..." -- that's below 95%. Stop and ask.

---

## Workflow

Defined in `.claude/rules/workflow.md` (auto-ingested). Covers build commands, launch process, git conventions, screenshot capture, and rich text serialization format.

---

## Subagent Architecture -- Context Window is Everything

**The primary law: the lead-agent context window is sacred. Never pollute it with lookups, searches, or doc reads.**

### Model Hierarchy

| Model      | Role                       | When to use                                                                                                                                                 |
| ---------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Opus**   | Lead agent (user-selected) | The hardest problems -- deep architecture decisions, ambiguous cross-cutting requirements, designs that need genuine reasoning. User selects Opus manually. |
| **Opus**   | Default lead agent         | Implementation, planning, multi-file edits, most features.                                                                                                  |
| **Sonnet** | Fire-and-forget worker     | Single-purpose lookups that have no business in the main context. Spin it and move on.                                                                      |

### Fire & Forget -- Delegation Rules

Spawn subagents immediately. Never block waiting for trivial information.

```
Haiku (fire immediately -- don't wait, don't think twice):
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

Opus (escalation only -- not parallel, not fire-and-forget):
- Escalate when Sonnet is genuinely stuck
- Consult before major architectural decisions
- User controls when Opus leads
```

### Hard Rules

1. **Information gathering never happens in main context.** Spawn Haiku, get result, use it.
2. **Parallelize all independent subagent calls.** Multiple Haiku agents running simultaneously is the goal.
3. **Sonnet asks Opus for help -- no shame in it.** Thrashing in main context is worse than escalating.
4. **Opus is user-selected as primary lead for the hardest work.** Sonnet runs day-to-day.
5. **Long file dumps, full grep results, entire doc pages = subagent territory.** Not here.

---

## Design System

-> **Always reference `.claude/rules/design-system.md`** for all color, spacing, typography, radius, and effect tokens.
-> Figma source: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot
-> Extract tokens for **both light and dark** themes. No exceptions.
-> **Always use the official Figma MCP plugin (`claude.ai Figma`) as the primary Figma tool.** Use `get_design_context`, `get_screenshot`, `get_metadata`, `get_variable_defs`, `search_design_system` for design tokens, component specs, and screenshots.

---

## Context Engineering

Before any feature implementation:

1. Write `INITIAL.md` describing the feature
2. `/generate-prp INITIAL.md`
3. `/execute-prp PRPs/feature-name.md`

---

## Tool Calling & Skills

**Always invoke the right skill before acting:**

| Task                            | Skills                                                                                                      |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| New feature                     | `superpowers:brainstorming` -> `superpowers:writing-plans` -> `superpowers:test-driven-development`         |
| Bug                             | `debugging` skill (reproduce-first -- see Bug Workflow below)                                               |
| Design / UI from Figma (Swift)  | `figma-to-swiftui` -> `figma-design` -> `frontend-design` (invoke all three -- Swift/SwiftUI projects only) |
| Design / UI from Figma (Web/RN) | `figma-design` -> `frontend-design` (invoke both -- web, React Native, websites, any non-Swift project)     |
| Icons (Swift)                   | Always download from Figma via `figma-to-swiftui` -- never use placeholders unless explicitly told          |
| Icons (Web/RN)                  | Always download from Figma via `figma-design` -- never use placeholders unless explicitly told              |
| Completion                      | `superpowers:verification-before-completion` -> `superpowers:requesting-code-review`                        |
| Multi-task                      | `superpowers:dispatching-parallel-agents`                                                                   |

**MCP / Plugin priority:**

1. Context7 -- SDK/API docs (always first)
2. Swift LSP plugin -- type lookups, jump-to-definition, symbol search, diagnostics, code intelligence. Use proactively for any Swift/SwiftUI code to verify types, protocols, and API signatures instead of guessing.
3. Official Figma MCP plugin (`claude.ai Figma`) -- design tokens, component specs, screenshots, variable definitions
4. Brave Search -- last resort

**Always parallelize** independent file reads, searches, and tool calls.

---

## Architecture

```
Jot/
├── App/              # JotApp, ContentView, AppDelegate, menu commands
├── Intents/          # App Intents for Shortcuts (create, open, search, append)
├── Models/           # Note, Folder, MeetingModels, SwiftData/
├── Views/
│   ├── Components/   # Reusable UI (~60 files)
│   │   └── Renderers/ # File preview renderers (audio, image, PDF, text, video)
│   └── Screens/      # Full-screen views
├── Utils/            # ThemeManager, FontManager, Extensions, GlassEffects
└── Ressources/       # Assets.xcassets (color sets)
```

Second asset catalog: `Jot/Assets.xcassets/` (icons, images, plus a few color tokens).

**Patterns:**

- State: `@StateObject` / `@EnvironmentObject` (NotesManager, ThemeManager)
- Persistence: `SimpleSwiftDataManager`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide
- View structure: props -> computed properties -> body
- Never hardcode design values -- always use asset catalog names
- Sidebar row height: 34pt for all note rows (NoteListCard, split containers, placeholders)
- Concentric corner radii: outer container 16, inner = outer - padding (e.g., pinned notes: container 16, padding 4, inner cards 12)
- Forced-appearance containers: split session containers use hardcoded `Color.white` + `.black` text (intentional -- theme-independent by design)
- Editor blocks (code/callout/tabs): NSTextAttachment + NSView overlay pattern

---

## Liquid Glass (iOS 26+ / macOS 26+)

Variants (from the `Glass` type):

- `.regular` -- default for toolbars, buttons, navigation (adapts to any content)
- `.clear` -- floating controls over media (photos, maps); needs bold foreground
- `.identity` -- disables glass conditionally (cleaner than if/else branching)

Modifiers (chain on any variant):

- `.tint(color)` -- semantic coloring integrated into the glass material
- `.interactive()` -- scaling, bounce, shimmer on press (interactive elements only)

Shapes: `Capsule()` (default), `RoundedRectangle(cornerRadius:)`, `Circle()`, `.rect(cornerRadius: .containerConcentric)`

Morphing: `.glassEffectID(id, in: namespace)` inside `GlassEffectContainer`

Helpers (in `GlassEffects.swift`):

- `liquidGlass(in:)` -- standard interactive glass
- `tintedLiquidGlass(in:tint:)` -- glass with native `.tint()` color
- `thinLiquidGlass(in:)` -- plain glass without interactivity
- `prominentGlassStyle()` -- `.glassProminent` button style
- `glassID(_:in:)` -- morphing ID wrapper
- Fallback: `.ultraThinMaterial` (pre-26 path)

Rules: no glass-on-glass; floating elements only; coordinate morphing with `GlassEffectContainer`.

---

## SVG Icon Rules

### Asset Catalog -- Required Properties

Every `.imageset/Contents.json` **must** include both flags in `properties`:

```json
"properties": {
  "template-rendering-intent": "template",
  "preserves-vector-representation": true
}
```

Without `preserves-vector-representation`, Xcode rasterizes SVGs as 1x bitmaps at build time. On Retina displays those bitmaps scale up = blur. **Always verify this when adding new icon assets.**

### Stroke Weight -- Consistency Formula

Target stroke ratio: `1/12` of viewBox size. Calculate: `stroke-width = viewBox_size / 12`.

| Figma grid | Correct stroke-width |
| ---------- | -------------------- |
| 10 x 10    | 0.833                |
| 12 x 12    | 1.0                  |
| 16 x 16    | 1.333                |
| 24 x 24    | 2.0                  |

Icons that deviate from this ratio will appear thinner or heavier than their siblings when scaled to the same SwiftUI frame. Fix the SVG source, not the frame size.

### SVG Rotation in SwiftUI

Figma may export SVGs in the wrong orientation. To rotate (e.g., horizontal to vertical):
`.frame(width: W, height: H).rotationEffect(.degrees(90)).frame(width: H, height: W)`

---

## Bug Workflow

When a bug is reported, **do not attempt to fix it immediately.** Instead:

1. Write a test that reproduces the bug (the test must fail).
2. Dispatch subagents to fix the bug and prove the fix with the now-passing test.
3. Only declare the bug fixed when the reproduction test passes.

---

## Code Rules

- Research the codebase before editing. Never change code you haven't read.
- No hardcoded colors, spacing, or radii -- use design tokens.
- Check existing components before creating new ones.
- Rich text: `AttributedString` + `.richTextCapabilities()`.
- Lists: `LazyVGrid` for performance.
- `NSColor.labelColor` everywhere -- no hardcoded dark/light RGB tuples.
- Broad codebase review before any bug fix -- never patch symptoms.
- Always use Context7 for SwiftUI/SDK documentation.
- Never `.clipped()` or `.clipShape()` on parent containers unless explicitly requested.

---

## CI / GitHub Actions

Workflows live at `.github/workflows/` -- this is a GitHub requirement and cannot move.

- `claude-code-review.yml` -- PR review bot
- `claude.yml` -- responds to `@claude` mentions in issues/PRs
