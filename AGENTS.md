---

## description:

alwaysApply: true

# Jot -- agent instructions

**Single source of truth:** edit `**AGENTS.md`** at the **repository root** only. `.claude/CLAUDE.md`, root `CLAUDE.md`, and root `claude.md` are symbolic links to this file so Claude Code, Cursor, and other tools share identical instructions.

iOS 26+ / macOS 26+ note-taking app in SwiftUI with Apple Liquid Glass design system.

---

## Forward Thinking -- READ BEFORE EVERYTHING ELSE

**This rule overrides convenience. It is the most important behavioral rule in this document.**

Every request -- no matter how small, trivial, or narrowly scoped it sounds -- must be evaluated from a **broad, system-wide perspective** before a single line is touched. The user will **not** spoon-feed every affected file, component, or edge case. That is **your job**. A request is a _signal_, not a specification.

### The mandate

When a change is requested, you must proactively ask yourself:

1. **What else shares this code path, token, component, or behavior?** A color tweak in one place likely implies the same treatment elsewhere. A spacing change on one card implies its siblings. A font-weight bump in one heading implies the scale.
2. **What visual or behavioral siblings exist?** If the change is to a sidebar row, examine every other sidebar row. If it's a button variant, check every button of that variant. If it's a toolbar, check every toolbar.
3. **What states and modes are affected?** Light vs dark. Hover vs active vs disabled. Compact vs expanded. First-responder vs not. Split-view vs single. Pinned vs unpinned. macOS 14 fallback vs 26+. You must check all of them.
4. **What upstream or downstream consumers depend on this?** Design tokens cascade. Shared modifiers cascade. A change to `ButtonSecondaryBgColor` touches every place that token is read. A change to a reusable component touches every call site.
5. **What does the Figma source say?** If the change is visual, the Figma file is the single source of truth. Check sibling frames, not just the one the user referenced.
6. **What invariants or conventions might this break?** Concentric radii. 34pt sidebar row height. `NSColor.labelColor` everywhere. Heading-font guards in `styleTodoParagraphs`. Glass-on-glass prohibition. If your change would break one of these, flag it.

### The behavior

- **Default to scope expansion, not scope compression.** When in doubt, do _more_ of the right thing, not less. A "fix this one button" request where you find five identical broken buttons should fix all five -- and then tell the user what you did and why.
- **Surface the implications before acting.** Before implementing, state: "This change also affects X, Y, and Z because [reason]. I'll update all of them unless you tell me otherwise." This is not asking permission -- it is informing.
- **Never ship a half-done change that visibly breaks parity.** If you restyle one variant and leave its siblings inconsistent, that is a regression, not a feature.
- **UI changes especially demand this.** Visual inconsistency is corrosive. A single mismatched radius, padding, or color ruins the whole surface. Treat UI work as a cascade, not an island.

### The forbidden posture

- "The user only asked about X, so I'll only change X" -- **wrong**. The user asked about X because X was visible. Your job is to find the full extent of what X implies.
- "I wasn't told to touch Y" -- **wrong**. You were told to think. If Y is clearly affected, touch Y.
- "I'll wait for the user to notice the inconsistency" -- **wrong**. That is spoon-feeding in reverse. The user expects you to see the whole board.

### The test

Before responding to any request, you must be able to answer: _"What other parts of this codebase, this UI, this token graph, or this behavior are implicated by this change -- and have I addressed all of them?"_ If the answer is "I didn't look," stop and look.

---

## Prohibited -- Read This First

These rules are absolute. No exceptions. No rationalizations. No "just this once."

1. **Never guess when debugging.** Every bug -- regardless of how trivial, minor, or "obvious" it seems -- requires root cause investigation before any fix is attempted. Dispatch subagents to research the problem. Read documentation. Check entitlements, plists, build settings, sandbox permissions. The cost of one proper investigation is always less than four wrong guesses. If you catch yourself thinking "let me just try changing X," stop. You are about to waste time.
2. **No log-based debugging.** Do not add `NSLog`, `print()`, `os_log`, or any temporary logging statements to diagnose issues. Logs pollute the codebase, require rebuild-relaunch cycles, and encourage guess-and-check instead of thinking. Use subagents to research the problem, read Apple documentation via Context7/WebSearch, check system configuration (entitlements, plist, sandbox), and reason about the architecture. If you need runtime observation, use Xcode's debugger, not log statements.
3. **No fix without root cause.** Proposing a fix before identifying the root cause is prohibited. "I think it might be X" is not a root cause. A root cause is: "The app sandbox requires `com.apple.security.print` for `NSPrintOperation` to function, and this entitlement is missing from Jot.entitlements." Specificity or silence.
4. **No unsolicited test runs, NSLog, or background monitoring.** Whatever model is selected: do not start test instances of the app or project (dev servers, simulators, preview hosts, or similar) unless the user explicitly asks. Do not add `NSLog` or other logging for diagnostics (rule 2 stands). Do not run or leave background monitoring of builds, processes, logs, or environment state unless the user explicitly requests it.

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
-> Figma source: [https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot](https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot)
-> Extract tokens for **both light and dark** themes. No exceptions.
-> See the **Design Tokens** section below for the full token reference.
-> **Always use the official Figma MCP plugin (`claude.ai Figma`) as the primary Figma tool.** Use `get_design_context`, `get_screenshot`, `get_metadata`, `get_variable_defs`, `search_design_system` for design tokens, component specs, and screenshots.
-> **Icons from a Figma link (`figma.com/design/...?node-id=...`):** Parse `fileKey` from the path and `nodeId` from the query (convert `2855-33` to `2855:33`). Call the Figma MCP tool **`get_design_context`** (Cursor: server **figma** / `plugin-figma-figma`). The response embeds asset URLs such as `https://www.figma.com/api/mcp/asset/<uuid>` — **download those files** (they are often SVG), normalize strokes to `currentColor` for template-rendering icons, add an explicit `18×18` transparent `<rect>` if Xcode’s asset catalog rejects the export (“zero width/height canvas”), and save into [`Jot/Assets.xcassets`](Jot/Assets.xcassets). **Never substitute a hand-drawn placeholder** when the user supplied a node URL.

---

## Context Engineering

Before any feature implementation:

1. Write `INITIAL.md` describing the feature
2. `/generate-prp INITIAL.md`
3. `/execute-prp PRPs/feature-name.md`

---

## Features -- New Feature Development (mandatory)

**This applies to every new feature implementation.** The **Superpowers** plugin skills define the canonical pipeline. **You must invoke, trigger, and execute them one by one in the order below** -- no skipping, batching, or reordering. Treat each step as complete only when its outcomes exist (questions answered, worktree ready, plan written, subagent work done, tests red-green, review done, branch finished).

**How skills relate to commands:** Superpowers is built so skills can **fire on context match** (no slash-command required in some setups). That is **automatic surfacing**, not permission to omit a phase. For feature work, still **walk the list top to bottom** and ensure each skill’s work actually runs.

### Superpowers pipeline (strict order)

| Step | Skill                                        | What to do                                                                                                                   |
| ---- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 1    | `superpowers:brainstorming`                  | Refine the spec with clarifying questions until requirements are unambiguous.                                                |
| 2    | `superpowers:using-git-worktrees`            | Use an isolated branch workspace per task (worktree per task, not shared dirty trees).                                       |
| 3    | `superpowers:writing-plans`                  | Break the design into **2–5 minute** tasks; each task should be small enough to implement and verify independently.          |
| 4    | `superpowers:subagent-driven-development`    | **Dispatch a fresh subagent per task**; do not accumulate unbounded context in the lead agent for implementation grunt work. |
| 5    | `superpowers:test-driven-development`        | **Red–Green–Refactor** is enforced: failing test first, then implementation, then cleanup.                                   |
| 6    | `superpowers:requesting-code-review`         | **Two-stage review per task** before treating the task as done.                                                              |
| 7    | `superpowers:finishing-a-development-branch` | Close the loop: **merge, open/land PR, or discard** -- never leave the branch in an ambiguous state.                         |

**Context Engineering** (`INITIAL.md`, PRP generate/execute) remains the artifact path for this repo; run it **in service of** the Superpowers pipeline (planning inputs for step 1 and step 3), not as a substitute for any Superpowers step.

---

## Tool Calling & Skills

**Always invoke the right skill before acting:**

| Task                            | Skills                                                                                                                                                                                                                                                                           |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New feature                     | **Full Superpowers pipeline in order** -- see **Features -- New Feature Development**: `brainstorming` -> `using-git-worktrees` -> `writing-plans` -> `subagent-driven-development` -> `test-driven-development` -> `requesting-code-review` -> `finishing-a-development-branch` |
| Bug                             | `debugging` skill (reproduce-first -- see Bug Workflow below)                                                                                                                                                                                                                    |
| Design / UI from Figma (Swift)  | `figma-to-swiftui` -> `figma-design` -> `frontend-design` (invoke all three -- Swift/SwiftUI projects only)                                                                                                                                                                      |
| Design / UI from Figma (Web/RN) | `figma-design` -> `frontend-design` (invoke both -- web, React Native, websites, any non-Swift project)                                                                                                                                                                          |
| Icons (Swift)                   | Always download from Figma via `figma-to-swiftui` -- never use placeholders unless explicitly told                                                                                                                                                                               |
| Icons (Web/RN)                  | Always download from Figma via `figma-design` -- never use placeholders unless explicitly told                                                                                                                                                                                   |
| Completion                      | `superpowers:verification-before-completion` -> `superpowers:requesting-code-review`                                                                                                                                                                                             |
| Multi-task                      | `superpowers:dispatching-parallel-agents`                                                                                                                                                                                                                                        |

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

**When to run builds:** Use `xcodebuild` when the user explicitly asks for a build, when they want the DEBUG in-app update flow (phrases like “rebuild for the update panel”, “refresh the running app”), when running tests, or when they asked you to confirm the project compiles. **Do not** run a Debug build automatically after every code change.

### DEBUG update panel (only when the user requests this flow)

When the user asks to rebuild so a **running DEBUG** instance can pick up changes, run from the repo root (short tail keeps logs readable):

```bash
cd /Users/mohebanwari/development/Jot && xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -8
```

**Why:** `BuildWatcherManager` (DEBUG only) watches `Jot.debug.dylib`. When the binary updates while the app is running, an **update panel can appear at the bottom of the left sidebar** (above Trash/Settings). The user relaunches from there.

**After any build — never:** `pkill` / `killall` Jot, `open` the app, `touch` the `.app` bundle, or otherwise force a relaunch. Same policy as `.cursor/rules/feedback_no_relaunch_after_build.mdc`.

**When the user requested this flow:** (1) run the command above, (2) confirm `BUILD SUCCEEDED`, (3) tell them the build is ready and they can use the sidebar update panel when they want.

Cursor mirrors this opt-in rule in `.cursor/rules/feedback_rebuild_for_update_panel.mdc` (`alwaysApply: false`).

---

## Git Conventions

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

---

## Figma Source

- Jot design file (always reference this):
  [https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot?node-id=0-1&p=f&t=Exr6XkLRSkF2tndZ-0](https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot?node-id=0-1&p=f&t=Exr6XkLRSkF2tndZ-0)

Suggested uses:

- Verify tokens (colors, typography) before changing assets.
- Align component specs (spacing, radii, effects) with the selected frame.
- Use as the single source of truth for light/dark variants and Liquid Glass behavior.

---

## Design Tokens

Single source of truth for design tokens. Extracted from Figma and xcassets.

### Color Tokens

All semantic colors live in `Jot/Ressources/Assets.xcassets/`. Reference by name in SwiftUI (`Color("TokenName")`). Always support both light and dark.

| Token                          | Light                              | Dark                               |
| ------------------------------ | ---------------------------------- | ---------------------------------- |
| `AccentColor`                  | `#2563EB`                          | `#608DFA`                          |
| `MainColor`                    | `#1A1A1A` (= ButtonPrimaryBgColor) | `#FFFFFF` (= ButtonPrimaryBgColor) |
| `BackgroundColor`              | `#FFFFFF5C` (36% white)            | `#0C0A0908` (3% near-black)        |
| `BlockContainerColor`          | `#D6D3D1` (stone-300)              | `#292524` (stone-800)              |
| `BorderSubtleColor`            | `#1A1A1A17` (9% black)             | `#FFFFFF17` (9% white)             |
| `ButtonPrimaryBgColor`         | `#1A1A1A`                          | `#FFFFFF`                          |
| `ButtonPrimaryTextColor`       | `#FFFFFF`                          | `#1A1A1A`                          |
| `ButtonSecondaryBgColor`       | `#D6D3D1` (stone-300)              | `#292524` (stone-800)              |
| `CardBackgroundColor`          | `#FFFFFFB3` (70% white)            | `#1C1918B3` (70% dark)             |
| `FolderBadgeBgColor`           | `#FFFFFF5C` (36% white)            | `#FFFFFF1F` (12% white)            |
| `HoverBackgroundColor`         | `#D1D3D0`                          | `#444040`                          |
| `IconSecondaryColor`           | `#1A1A1AB3` (70% black)            | `#A8A29E`                          |
| `InlineCodeBgColor`            | `#93C5FD` (blue-300)               | `#1E40AF` (blue-800)               |
| `MenuButtonColor`              | `#1A1A1AB3` (70% black)            | `#FFFFFFB3` (70% white)            |
| `PinnedBgColor`                | `#FEF08A` (amber)                  | `#854D0E` (amber-dark)             |
| `PinnedIconColor`              | `#854D0E`                          | `#FEEF8A`                          |
| `PrimaryTextColor`             | `#1A1A1A`                          | `#FFFFFF`                          |
| `SearchInputBackgroundColor`   | `#FFFFFF`                          | `#1C1918`                          |
| `SecondaryBackgroundColor`     | `#E7E6E4`                          | `#292524`                          |
| `SecondaryTextColor`           | `#1A1A1AB3` (70% black)            | `#FFFFFFB3` (70% white)            |
| `SettingsActiveTabColor`       | `#F5F4F4`                          | `#444040`                          |
| `SettingsIconSecondaryColor`   | `#1A1A1AB3`                        | `#A8A29E`                          |
| `SettingsOptionCardColor`      | `#E7E6E4`                          | `#0C0A09`                          |
| `SettingsPanelPrimaryColor`    | `#FFFFFF5C` (36% white)            | `#1A1A1ACC` (80% black)            |
| `SettingsPlaceholderTextColor` | `#1A1A1AB3`                        | `#FFFFFFB2`                        |
| `SettingsPrimaryTextColor`     | `#1A1A1A`                          | `#FFFFFF`                          |
| `SurfaceDefaultColor`          | `#FFFFFF`                          | `#1C1918`                          |
| `SurfaceElevatedColor`         | `#F5F4F4`                          | `#292524`                          |
| `SurfaceTranslucentColor`      | `#1A1A1A0F` (6% black)             | `#FFFFFF0F` (6% white)             |
| `TagBackgroundColor`           | `#608DFA59` (35% accent)           | `#608DFA40` (25% accent)           |
| `TagTextColor`                 | `#1A1A1A`                          | `#FFFFFF`                          |
| `TertiaryTextColor`            | `#52525B`                          | `#A19FA9`                          |

#### Primitive Colors (Figma Variables)

```
blue/500     #3B82F6
red/500      #EF4444
icon/blue    #3B82F6
```

### Typography

All type uses **SF Pro**. Weights: Regular=400, Medium=500, SemiBold=600, Bold=700.

#### Figma Type Scale

| Style      | Size | Line Height | Tracking | Weights Available |
| ---------- | ---- | ----------- | -------- | ----------------- |
| Heading/H4 | 20   | 24          | -0.20    | Medium            |
| Label-2    | 15   | 18          | -0.50    | Medium            |
| Label-3    | 13   | 16          | -0.40    | Medium            |
| Label-4    | 12   | 14          | -0.30    | Medium, SemiBold  |
| Label-5    | 11   | 14          | -0.20    | Medium            |
| Tiny       | 10   | 12          | 0        | Medium, SemiBold  |
| Micro      | 9    | 10          | 0        | SemiBold, Bold    |

#### FontManager API (code-level)

Three font families: **Charter** (serif body), **SF Pro** (headings/UI), **SF Mono** (metadata/code).

| Method       | SwiftUI                          | Size | Weight  | Notes                           |
| ------------ | -------------------------------- | ---- | ------- | ------------------------------- |
| `body()`     | `Font.custom("Charter", size:)`  | 16   | Regular | Follows `bodyFontStyle` setting |
| `heading()`  | `Font.system(size:, weight:)`    | 24   | Medium  | Respects `bodyFontStyle`        |
| `metadata()` | `Font.system(monospaced, size:)` | 12   | Medium  | Timestamps, dates               |
| `icon()`     | `Font.system(size:)`             | 20   | Regular | SF Symbols                      |

Body font style is user-configurable: `default` (Charter), `system` (SF Pro), `mono` (SF Mono).
Line spacing presets: Compact (1.0x), Default (1.2x), Relaxed (1.5x) -- stored in `ThemeManager.lineSpacing`.

### Spacing Scale

Figma token name -> pt value:

| Token  | Value |
| ------ | ----- |
| `zero` | 0     |
| `xxs`  | 2     |
| `xs2`  | 4     |
| `xs`   | 8     |
| `sm`   | 12    |
| `base` | 16    |
| `xl2`  | 32    |
| `xl4`  | 48    |
| `xl5`  | 60    |

Canonical padding values in use: `4, 6, 8, 12, 16, 18, 24, 60`

### Corner Radius Scale

| Token  | Value         |
| ------ | ------------- |
| `none` | 0             |
| `lg`   | 8             |
| `xl`   | 12            |
| `2xl`  | 16            |
| `md`   | 20            |
| `3xl`  | 24            |
| `full` | 999 (capsule) |

Canonical radius values in use: `4, 20, 24, Capsule`

### Effects

| Token          | Value                     |
| -------------- | ------------------------- |
| `bg-blur/tags` | Background blur, radius 4 |

### Animations & Timing

All in `Extensions.swift`:

| Animation         | Response | Damping | Duration | Usage                              |
| ----------------- | -------- | ------- | -------- | ---------------------------------- |
| **jotSpring**     | 0.35s    | 0.82    | -        | Spring response for natural motion |
| **jotBounce**     | -        | -       | 0.3s     | Bouncy easing                      |
| **jotSmoothFast** | -        | -       | 0.2s     | Fast linear transitions            |
| **jotHover**      | 0.25s    | 0.75    | -        | Hover state animations (subtle)    |
| **jotDragSnap**   | 0.18s    | 0.9     | -        | Drag-release snap-to-grid effect   |

### Liquid Glass Tokens (iOS 26+ / macOS 26+)

Glass behavior is governed by native `.glassEffect()`. Not a color token -- a modifier.

```swift
// Standard
.glassEffect()

// Custom shape
.glassEffect(.thin, in: RoundedRectangle(cornerRadius: 20))

// Interactive
.glassEffect(.regular.interactive(true))

// Coordinated morphing
.glassEffectID("toolbar", in: namespace)
```

**Rules:**

- Apply to floating elements only (toolbars, cards, overlays)
- Never stack glass on glass -- use `.implicit` display mode
- Avoid in scrollable content
- Use `.bouncy` / `.smooth` spring animations for state changes

### Asset Catalog Locations

| Content         | Path                              |
| --------------- | --------------------------------- |
| Semantic colors | `Jot/Ressources/Assets.xcassets/` |
| Icons & images  | `Jot/Assets.xcassets/`            |
| SVG icons       | `Jot/` (root-level .svg files)    |
